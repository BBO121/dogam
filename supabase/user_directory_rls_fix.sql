-- ============================================
-- 회원 login_id(로그인 아이디) 익명/일반유저 대량 노출 차단
-- 작성일: 2026-08-14 / 수정: 2026-08-14(DROP FUNCTION 방식으로 재작성)
--
-- 문제:
--   get_all_users_full() — GRANT ... TO anon 상태로, 비로그인 상태에서도
--     전체 회원의 id/nickname/login_id/role/created_at을 그대로 반환.
--   get_all_users()      — anon 호출이 가능하고 login_id를 포함해 반환함.
--     캐릭터/종족 등록·수정·이전 페이지 등 25개 이상에서 사용 중이나,
--     그중 실제로 login_id 값을 쓰는 곳은 소수(검색 자동완성 표시/매칭, my-species.html
--     owner_id 링크, 대량이전 3종의 일괄 매칭)뿐이고 나머지는 id/nickname/role만 사용한다.
--   search_users()        — supabase/search_setup.sql로 이미 배포된 헤더 통합검색용 RPC.
--     이것도 anon+authenticated 모두에게 login_id를 그대로 반환하고 있었다
--     (조사 보고서에는 없던 문제 — 이번에 코드 전수 확인 중 추가로 발견함).
--
-- ✅ get_all_users()의 실제 라이브 정의를 뽀가 pg_get_functiondef로 직접 확인해줌
--    (2026-08-14). 아래는 그 실제 정의를 기준으로 login_id만 제거한 것입니다
--    (WHERE 조건, nickname/role 계산식, LANGUAGE, ORDER BY 없음 등 전부 원본과 동일).
--
-- ⚠️ [2026-08-14 재수정] PostgreSQL은 CREATE OR REPLACE FUNCTION으로
--    RETURNS TABLE의 컬럼 구성(반환 타입)을 바꿀 수 없습니다 — login_id 컬럼을
--    빼는 것 자체가 반환 타입 변경이라, get_all_users_full() / get_all_users() /
--    search_users(text,int) 세 함수는 전부 CREATE OR REPLACE로 실행하면 에러가 납니다.
--    (delete_user()는 반환 타입이 그대로 void라 CREATE OR REPLACE로도 문제없어
--     supabase/delete_user_fix_authz.sql은 수정하지 않았습니다.)
--    → 이 세 함수만 DROP FUNCTION(정확한 시그니처, CASCADE 없음) 후 재생성하고,
--    DROP으로 함께 사라지는 GRANT를 재생성 직후 다시 부여하도록 바꿨습니다.
--    DROP FUNCTION은 기본이 RESTRICT라, 만약 이 함수들에 의존하는 뷰/함수가
--    있다면 조용히 지워지는 게 아니라 에러를 내며 멈춥니다(안전).
--
-- 방향:
--   1) get_all_users() / get_all_users_full() — login_id를 응답에서 제거.
--      GRANT는 그대로 둔다(anon 포함) — 이미 25개 이상 페이지가 id/nickname/role만
--      사용 중이라 이 두 함수를 쓰는 대부분의 화면은 호출부 변경 없이 그대로 동작한다.
--   2) search_users(query, limit) — 기존 함수에서 login_id만 응답에서 제거.
--      캐릭터/디자이너 검색 자동완성, my-species.html owner_id 링크, DM 새 대화 검색을
--      전부 이 기존 RPC(js/search.js의 searchUsers 헬퍼)로 전환해 중복 구현을 없앴다.
--   3) resolve_users_by_identifiers(identifiers) / resolve_users_by_ids(ids) 신규 —
--      "검색"이 아니라 "이미 알고 있는 식별자 목록을 한 번에 매칭"이 필요한 곳 전용
--      (대량이전 도구의 붙여넣은 목록 일괄 매칭 — admin/staff 전용, 캐릭터 편집 화면의
--      기존 designer_user_ids(uuid) 표시용 — 로그인 유저 전체 허용).
--      전체 목록을 클라이언트로 내려주지 않고 서버에서 매칭만 해서 돌려준다.
--      이 둘은 원래 없던 신규 함수라 CREATE OR REPLACE 그대로 둬도 안전합니다.
-- ============================================


-- ============================================
-- 0. (읽기 전용, 먼저 실행) 의존성 확인
--
-- 레포의 SQL 파일 전수 검색으로는 이 세 함수를 참조하는 다른 뷰/함수를
-- 찾지 못했습니다. 다만 get_all_users()처럼 Dashboard에서만 만들어지고
-- 레포에 흔적이 없는 객체가 있을 수 있어, 아래를 먼저 돌려서 실제로
-- 아무것도 안 나오는지 확인해주세요. 뭔가 나오면(빈 결과가 아니면)
-- DROP 전에 저한테 결과를 알려주세요 — 그 객체를 먼저 처리해야 합니다.
-- ============================================
SELECT
  pg_describe_object(d.classid, d.objid, d.objsubid) AS dependent_object,
  d.deptype
FROM pg_depend d
WHERE d.refobjid IN (
  'public.get_all_users()'::regprocedure,
  'public.get_all_users_full()'::regprocedure,
  'public.search_users(text, int)'::regprocedure
)
AND d.deptype = 'n'  -- 'n' = normal dependency(뷰/함수 등이 이 함수를 실제로 참조하는 경우). 'i'(internal) 등은 제외.
ORDER BY dependent_object;
-- 결과가 0행이어야 아래 DROP이 안전합니다.


-- ============================================
-- 1. get_all_users_full() — DROP 후 재생성(login_id 제거)
-- ============================================
DROP FUNCTION public.get_all_users_full();

CREATE FUNCTION get_all_users_full()
RETURNS TABLE (
  id          uuid,
  nickname    text,
  role        text,
  created_at  timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    u.id,
    NULLIF(TRIM(COALESCE(
      u.raw_user_meta_data->>'display_name',
      u.raw_user_meta_data->>'nickname',
      ''
    )), '') AS nickname,
    u.raw_user_meta_data->>'role' AS role,
    u.created_at
  FROM auth.users u
  WHERE u.deleted_at IS NULL
  ORDER BY u.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION get_all_users_full() TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_users_full() TO anon;


-- ============================================
-- 2. get_all_users() — DROP 후 재생성(login_id 제거)
--    뽀가 확인해준 실제 라이브 정의(pg_get_functiondef, 2026-08-14) 그대로이며
--    RETURNS TABLE에서 login_id만 빼고 SELECT 목록에서 해당 항목만 제거했습니다.
--    WHERE 조건, nickname/role 계산식, LANGUAGE, GRANT는 원본과 동일합니다
--    (원본에도 ORDER BY와 SET search_path가 없어서 그대로 뒀습니다).
-- ============================================
DROP FUNCTION public.get_all_users();

CREATE FUNCTION public.get_all_users()
RETURNS TABLE(id uuid, nickname text, role text, created_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
      BEGIN
        RETURN QUERY
        SELECT
          au.id,
          COALESCE(
            raw_user_meta_data->>'display_name',
            raw_user_meta_data->>'nickname'
          ) AS nickname,
          COALESCE(raw_user_meta_data->>'role', '') AS role,
          au.created_at
        FROM auth.users au
        WHERE raw_user_meta_data->>'nickname' IS NOT NULL;
      END;
      $function$;

GRANT EXECUTE ON FUNCTION get_all_users() TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_users() TO anon;


-- ============================================
-- 3. search_users(text, int) — DROP 후 재생성(login_id 제거)
--
-- ⚠️ 중요: 이 RPC는 신규가 아니라 헤더 통합검색(js/search.js searchUsers(),
--    js/main.js)이 이미 쓰고 있는 기존 함수입니다. search_setup.sql의 정의를
--    그대로 가져와 login_id만 응답에서 제거했습니다 — 그 외 동작(오타/특수문자
--    이스케이프, 관련도 정렬, is_species_owner, total_count, pg_trgm 인덱스 활용)은
--    전혀 바꾸지 않았습니다. anon GRANT도 기존 그대로 유지합니다 — 이 RPC의
--    문제는 "비로그인에게 검색 자체를 열어준 것"이 아니라(닉네임은 이미
--    users.html 등에서 비로그인에게도 공개되는 정보) "검색 결과에 로그인
--    아이디까지 얹어 보낸 것"이므로, login_id 필드 제거만으로 충분합니다.
--    login_id는 매칭(WHERE/ORDER BY)에는 계속 쓰되 응답 컬럼에서는 뺍니다.
--
--    캐릭터/종족 등록·수정·이전, DM 새 대화 검색 등 기존에 get_all_users()로
--    전체 목록을 받아 클라이언트에서 필터링하던 화면들도 전체 목록 대신
--    이 RPC를 호출하도록 함께 전환했습니다(js/search.js의 searchUsers(query,
--    {limit, minLength}) 헬퍼를 그대로 재사용 — 새 헬퍼를 따로 만들지 않았습니다).
--
--    정확한 시그니처: search_users(p_query text, p_limit int) — p_limit에 기본값
--    DEFAULT 10이 있어도 DROP FUNCTION 매칭에는 타입(text, int)만 쓰면 됩니다.
-- ============================================
DROP FUNCTION public.search_users(text, int);

CREATE FUNCTION public.search_users(p_query text, p_limit int DEFAULT 10)
RETURNS TABLE (
  id                uuid,
  nickname          text,
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
    SELECT
      NORMALIZE(TRIM(COALESCE(p_query, '')), NFC) AS q_raw,
      LEAST(GREATEST(COALESCE(p_limit, 10), 1), 50) AS result_limit
  ),
  esc AS (
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
    f.role,
    up.avatar_url,
    (
      f.role = 'species_owner'
      OR EXISTS (SELECT 1 FROM public.species s WHERE s.owner_nickname = f.nickname)
    ) AS is_species_owner,
    COUNT(*) OVER() AS total_count
  FROM filtered f
  LEFT JOIN public.user_profiles up ON up.user_id = f.id
  ORDER BY
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
GRANT EXECUTE ON FUNCTION public.search_users(text, int) TO anon;
GRANT EXECUTE ON FUNCTION public.search_users(text, int) TO authenticated;


-- ============================================
-- 4. resolve_users_by_identifiers(identifiers) 신규
--    admin/staff 전용. 대량이전 도구의 일괄 매칭용.
--    (기존에 없던 함수 이름이라 CREATE OR REPLACE 그대로 사용 — DROP 불필요)
--
-- ⚠️ 이후 두 차례 더 패치됨 — 이 아래 정의는 라이브 정의가 아닙니다.
--    1) supabase/privacy_fix_patch2.sql: search_path='' + schema-qualified로 재생성
--    2) supabase/fix_resolve_users_identifiers_nfc.sql (2026-08-15): 매칭 조건에
--       유니코드 정규화(NFC) 추가 — 한글 NFC/NFD 표현 차이로 매칭 실패하던 문제 수정.
--    현재 정의는 fix_resolve_users_identifiers_nfc.sql을 참고하세요.
--
--    matched_identifier(입력한 원본 문자열)를 함께 반환한다 — login_id는 응답에
--    포함하지 않으므로, 클라이언트가 "어떤 입력값이 어떤 유저에 매칭됐는지"를
--    다시 구성하려면 이 매칭 키가 필요하다(닉네임만으로는 login_id로 매칭된
--    건을 구분할 수 없음). 대소문자/좌우공백은 서버에서 정규화해 비교하므로
--    클라이언트는 원본 identifiers 배열의 문자열을 그대로 키로 써서 lookup하면 된다.
--
--    [2026-08-14 수정] admin 2명 + staff 4명(율하/모로/냐수/이상어)의
--    raw_app_meta_data.role 마이그레이션이 완료된 것을 뽀가 확인해줘서,
--    raw_user_meta_data.role 폴백을 제거하고 app_metadata만 신뢰하도록 변경.
-- ============================================
CREATE OR REPLACE FUNCTION resolve_users_by_identifiers(p_identifiers text[])
RETURNS TABLE (
  matched_identifier text,
  id                  uuid,
  nickname            text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  SELECT raw_app_meta_data->>'role'
  INTO v_caller_role
  FROM auth.users WHERE id = auth.uid();

  IF auth.uid() IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '관리자만 실행할 수 있습니다.';
  END IF;

  IF p_identifiers IS NULL OR array_length(p_identifiers, 1) IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT ident.x AS matched_identifier, sub.id, sub.nickname
  FROM unnest(p_identifiers) AS ident(x)
  JOIN (
    SELECT
      u.id,
      NULLIF(TRIM(COALESCE(
        u.raw_user_meta_data->>'display_name',
        u.raw_user_meta_data->>'nickname',
        ''
      )), '') AS nickname,
      COALESCE(
        NULLIF(TRIM(u.raw_user_meta_data->>'login_id'), ''),
        SPLIT_PART(u.email, '@', 1)
      ) AS login_id
    FROM auth.users u
    WHERE u.deleted_at IS NULL
  ) sub
    ON lower(sub.nickname) = lower(TRIM(ident.x))
    OR lower(sub.login_id) = lower(TRIM(ident.x));
END;
$$;

REVOKE ALL ON FUNCTION resolve_users_by_identifiers(text[]) FROM public;
GRANT EXECUTE ON FUNCTION resolve_users_by_identifiers(text[]) TO authenticated;


-- ============================================
-- 5. resolve_users_by_ids(ids) 신규
--    로그인 유저 전용, role 제한 없음. 이미 알고 있는 UUID(예: 캐릭터에 저장된
--    designer_user_ids)를 화면 표시용 닉네임으로 바꿀 때 사용한다.
--    UUID는 추측/열거가 사실상 불가능하고 id+nickname은 get_all_users()로도
--    이미 공개되는 정보라 role 제한 없이 authenticated 전체에 허용한다.
--    (기존에 없던 함수 이름이라 CREATE OR REPLACE 그대로 사용 — DROP 불필요)
-- ============================================
CREATE OR REPLACE FUNCTION resolve_users_by_ids(p_ids uuid[])
RETURNS TABLE (
  id       uuid,
  nickname text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    u.id,
    NULLIF(TRIM(COALESCE(
      u.raw_user_meta_data->>'display_name',
      u.raw_user_meta_data->>'nickname',
      ''
    )), '') AS nickname
  FROM auth.users u
  WHERE u.deleted_at IS NULL
    AND p_ids IS NOT NULL
    AND u.id = ANY(p_ids);
$$;

REVOKE ALL ON FUNCTION resolve_users_by_ids(uuid[]) FROM public;
GRANT EXECUTE ON FUNCTION resolve_users_by_ids(uuid[]) TO authenticated;
