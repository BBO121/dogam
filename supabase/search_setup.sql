-- 통합 검색 시스템 구축
-- 배경: 개체 검색 시 characters 테이블이 정렬/limit 없이 조회되어
--       PostgREST 기본 1,000행 캡에 걸려 최근 등록/수정된 행이
--       누락되는 문제가 있었음 (예: id=1410 "해체하라", 전체 1,604행 중
--       기본 정렬 없는 조회의 첫 1,000행 밖에 위치).
--       이를 서버 측 ILIKE 검색 + 명시적 정렬/페이징으로 대체한다.
--
-- 적용 방법: Supabase 대시보드 > SQL Editor 에서 이 파일 전체를 실행.
-- pg_trgm은 Supabase 프로젝트에 기본 포함된 확장이라 별도 승인 없이
-- CREATE EXTENSION 이 성공해야 합니다 (실패 시 Database > Extensions
-- 탭에서 pg_trgm 사용 가능 여부를 먼저 확인해주세요).

-- ── 1. pg_trgm 확장 (부분 문자열 ILIKE 검색 성능용 GIN 인덱스에 필요) ──
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ── 2. 개체(characters) 검색 인덱스 ──
-- name: 개체명 검색, owner_nickname: 소유주 통합 검색(기존 기능 유지)에 사용
CREATE INDEX IF NOT EXISTS idx_characters_name_trgm
  ON public.characters USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_characters_owner_nickname_trgm
  ON public.characters USING gin (owner_nickname gin_trgm_ops);

-- ── 3. 종족(species) 검색 인덱스 ──
CREATE INDEX IF NOT EXISTS idx_species_name_trgm
  ON public.species USING gin (name gin_trgm_ops);

-- ── 4. 유저 검색 RPC ──
-- auth.users는 PostgREST로 직접 조회할 수 없고(스키마 비공개),
-- 닉네임/아이디도 raw_user_meta_data(jsonb) 안에 있어 SECURITY DEFINER
-- 함수로 감싸서 필요한 컬럼만 안전하게 반환한다.
--
-- 닉네임  = display_name, 없으면 nickname (기존 get_all_users_full과 동일 규칙)
-- 아이디  = login_id 메타데이터, 없으면 이메일 앞부분(SPLIT_PART)
--          (현재 앱은 login_id 메타데이터를 별도로 설정하지 않으므로
--           사실상 가입 시 입력한 "아이디" = 이메일 프리픽스와 항상 동일함)
-- 이메일 원문은 절대 반환하지 않는다.
--
-- role은 기존 코드베이스(get_all_users_full.sql, admin_logs_setup.sql 등)와
-- 동일하게 raw_user_meta_data 기준으로 유지한다. raw_user_meta_data는
-- 유저 본인이 supabase.auth.updateUser()로 직접 수정 가능한 필드라 권한
-- 판단용으로는 근본적으로 안전하지 않지만, 이는 이 앱 전체의 권한 모델
-- 문제이므로 이 RPC 하나만 raw_app_meta_data로 바꿔도 실제로는 고쳐지지
-- 않고(현재 앱이 role을 raw_app_meta_data에 전혀 쓰지 않아 뱃지만
-- 조용히 사라짐) — 별도의 권한 모델 마이그레이션 작업으로 다룬다.
CREATE OR REPLACE FUNCTION public.search_users(p_query text, p_limit int DEFAULT 10)
RETURNS TABLE (
  id                uuid,
  nickname          text,
  login_id          text,
  role              text,
  avatar_url        text,
  is_species_owner  boolean,
  total_count       bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  WITH params AS (
    -- q_raw: 동등/접두 비교(관련도 정렬)용 — 트림 + NFC 정규화만 적용
    -- result_limit: 1~50 사이로 클램프 (anon에게도 열려있는 RPC라 상한 필요)
    SELECT
      NORMALIZE(TRIM(COALESCE(p_query, '')), NFC) AS q_raw,
      LEAST(GREATEST(COALESCE(p_limit, 10), 1), 50) AS result_limit
  ),
  esc AS (
    -- q_escaped: ILIKE 패턴 비교용 — LIKE 와일드카드(%, _, \)를 리터럴로
    -- 취급하기 위한 이스케이프. 반드시 백슬래시부터 먼저 이스케이프해야
    -- 뒤 단계에서 추가한 백슬래시가 다시 이스케이프되는 것을 방지할 수 있다.
    SELECT
      p.q_raw,
      p.result_limit,
      replace(replace(replace(
        p.q_raw,
        '\', '\\'),
        '%', '\%'),
        '_', '\_'
      ) AS q_escaped
    FROM params p
  ),
  matched AS (
    SELECT
      u.id,
      COALESCE(
        NULLIF(TRIM(u.raw_user_meta_data->>'display_name'), ''),
        NULLIF(TRIM(u.raw_user_meta_data->>'nickname'), '')
      ) AS nickname,
      COALESCE(
        NULLIF(TRIM(u.raw_user_meta_data->>'login_id'), ''),
        SPLIT_PART(u.email, '@', 1)
      ) AS login_id,
      NULLIF(TRIM(u.raw_user_meta_data->>'role'), '') AS role,
      u.created_at
    FROM auth.users u
    WHERE u.deleted_at IS NULL
  ),
  filtered AS (
    SELECT
      m.*,
      e.q_raw,
      e.q_escaped,
      e.result_limit
    FROM matched m
    CROSS JOIN esc e
    WHERE
      e.q_raw <> ''
      AND (
        m.nickname ILIKE '%' || e.q_escaped || '%' ESCAPE '\'
        OR m.login_id ILIKE '%' || e.q_escaped || '%' ESCAPE '\'
      )
  )
  SELECT
    f.id,
    f.nickname,
    f.login_id,
    f.role,
    up.avatar_url,
    -- 종족주 뱃지: role='species_owner' 이거나, 레거시 데이터로 role은
    -- 비어있지만 실제로 소유 중인 종족이 있는 경우(js/main.js의 기존
    -- speciesOwnerNicksSet 폴백 로직과 동일한 기준)
    (
      f.role = 'species_owner'
      OR EXISTS (SELECT 1 FROM public.species s WHERE s.owner_nickname = f.nickname)
    ) AS is_species_owner,
    COUNT(*) OVER() AS total_count
  FROM filtered f
  LEFT JOIN public.user_profiles up ON up.user_id = f.id
  ORDER BY
    -- 관련도: 정확 일치 → 접두 일치 → 포함 일치.
    -- q_raw(이스케이프 안 된 원본)로 비교해야 검색어에 %, _, \가 섞여도
    -- 정확/접두 판정이 어긋나지 않는다(ILIKE 패턴이 아니라 리터럴 비교).
    CASE
      WHEN LOWER(f.nickname) = LOWER(f.q_raw)
        OR LOWER(f.login_id) = LOWER(f.q_raw)
        THEN 0
      WHEN starts_with(LOWER(f.nickname), LOWER(f.q_raw))
        OR starts_with(LOWER(f.login_id), LOWER(f.q_raw))
        THEN 1
      ELSE 2
    END,
    f.created_at DESC
  LIMIT (SELECT result_limit FROM params);
$$;

REVOKE ALL ON FUNCTION public.search_users(text, int) FROM PUBLIC;

-- 비로그인 상태에서도 헤더 유저 검색이 필요할 경우에만 유지
GRANT EXECUTE ON FUNCTION public.search_users(text, int) TO anon;
GRANT EXECUTE ON FUNCTION public.search_users(text, int) TO authenticated;
