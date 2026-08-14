-- ============================================
-- resolve_users_by_identifiers() 한글 닉네임/아이디 매칭 실패 수정
-- 작성일: 2026-08-15
--
-- 문제:
--   젤피렐라 대량 소유권 이전 도구에서 실제 존재하는 유저("무명",
--   uuid=5ef47577-744a-4194-af72-d4e4ebfe790a)가 "유저를 찾지 못함"으로
--   나오는 문제 발견.
--
-- 원인:
--   resolve_users_by_identifiers()가 닉네임/아이디를 lower(btrim(x))로만
--   비교하고, 유니코드 정규화(NFC/NFD)를 하지 않음. 같은 글자라도
--   완성형(NFC)/조합형(NFD) 표현이 다르면 바이트가 달라 매칭 실패.
--   전각공백(U+3000)·NBSP(U+00A0)·zero-width space류(U+200B/200C/200D/FEFF)가
--   섞여도 btrim이 못 걸러내 같은 증상 발생 가능.
--   반면 이미 배포된 search_users()(supabase/user_directory_rls_fix.sql,
--   search_setup.sql)는 NORMALIZE(..., NFC)를 이미 쓰고 있어 이 문제가 없음.
--
-- 전제:
--   supabase/privacy_fix_patch2.sql이 이미 라이브에 적용되어 있다고 보고
--   그 버전(SET search_path = '', pg_catalog 스키마 한정)을 기준으로
--   CREATE OR REPLACE 함. 시그니처/반환 타입은 그대로라 CREATE OR REPLACE로
--   안전하게 교체 가능(DROP 불필요 — 기존 GRANT도 그대로 유지됨).
--
-- ⚠️ STEP 0을 먼저 실행해서 라이브 정의가 이 전제와 같은지 반드시 확인하세요.
--    다르면 STEP 1을 실행하지 말고 결과를 알려주세요.
--
-- 변경 요약:
--   1) 신규 헬퍼 함수 public._normalize_match_text(text) 추가 — 하나의
--      정규화 로직을 입력 identifier / nickname / login_id 세 곳에서 공용으로
--      사용(중복 구현 방지). zero-width류 문자 제거 → 공백/NBSP/전각공백
--      트림 → NFC 정규화 → lower() 순서로 처리.
--      눈에 안 보이는 문자는 소스에 직접 넣지 않고 U&'\XXXX' 유니코드
--      이스케이프로만 명시해서(편집기/git 표시에 안전) 어떤 문자를 다루는지
--      항상 코드로 확인 가능하게 함.
--      NORMALIZE(...) 구문은 이미 배포된 search_users()와 동일하게
--      SET search_path = pg_catalog로 안전하게 사용(빈 문자열 search_path에서
--      NORMALIZE가 이름 조회를 필요로 하는지 불확실성을 피하기 위함 —
--      search_users()가 이미 이 조합으로 라이브에서 정상 동작 중인 걸 근거로 함).
--      PUBLIC/anon/authenticated 전부에서 EXECUTE 제거 — 이 함수는
--      resolve_users_by_identifiers() 내부(SECURITY DEFINER, 소유자 권한으로
--      실행됨)에서만 쓰이므로 외부에서 직접 호출할 필요가 없음(최소 권한).
--   2) resolve_users_by_identifiers()의 매칭 조건만 위 헬퍼를 쓰도록 교체.
--      권한 체크(admin/staff), 반환 컬럼(matched_identifier/id/nickname),
--      SECURITY DEFINER/STABLE/search_path 설정은 전혀 바꾸지 않음.
--      GRANT/REVOKE도 이 함수에 대해서는 재실행하지 않음(시그니처 불변이라
--      CREATE OR REPLACE로 기존 권한이 그대로 유지되고, 실수로 권한 목록을
--      다르게 적는 위험을 원천 차단하기 위해 의도적으로 생략함).
--   3) [2026-08-15 추가 발견 — 진짜 원인] 실제 화면에서 재현한 결과
--      "column reference \"id\" is ambiguous"(42702) 에러로 RPC 호출 자체가
--      실패하고 있었음이 드러남. 원인은 patch2에 원래부터 있던 권한 체크
--      코드의 `FROM auth.users WHERE id = auth.uid()` — 이 함수의
--      RETURNS TABLE에 `id`라는 리턴 컬럼이 있어서, 한정자 없는 `id`가
--      "auth.users.id"인지 "함수 리턴 변수 id"인지 PL/pgSQL이 판단하지
--      못해 매 호출마다 예외가 났던 것. `auth.users.id`로 명시 한정해서
--      해결함(1)/2)의 정규화 로직과는 무관한 별개 버그).
--      이 버그는 patch2 배포(2026-08-15) 시점부터 있던 것으로 보이며,
--      정규화 문제와 무관하게 이 RPC를 쓰는 대량이전 도구 3종 전체가
--      그동안 어떤 유저도 제대로 매칭하지 못했을 가능성이 있음.
-- ============================================


-- ════════════════════════════════════════════════════════
-- STEP 0 — 실행 전 확인(읽기 전용). 라이브 정의가 privacy_fix_patch2.sql
-- 버전과 같은지 눈으로 확인해주세요(SET search_path = '' 여부, pg_catalog
-- 스키마 한정 여부). 다르면 STEP 1을 실행하지 말고 알려주세요.
-- ════════════════════════════════════════════════════════
SELECT pg_get_functiondef('public.resolve_users_by_identifiers(text[])'::regprocedure);


-- ════════════════════════════════════════════════════════
-- STEP 1 — 적용
-- ════════════════════════════════════════════════════════
BEGIN;

CREATE OR REPLACE FUNCTION public._normalize_match_text(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $$
  SELECT pg_catalog.lower(
    NORMALIZE(
      pg_catalog.btrim(
        pg_catalog.replace(
          pg_catalog.replace(
            pg_catalog.replace(
              pg_catalog.replace(COALESCE(p_text, ''), U&'\200B', ''),  -- ZERO WIDTH SPACE
              U&'\200C', ''  -- ZERO WIDTH NON-JOINER
            ),
            U&'\200D', ''  -- ZERO WIDTH JOINER
          ),
          U&'\FEFF', ''  -- ZERO WIDTH NO-BREAK SPACE / BOM
        ),
        U&'\0020\00A0\3000'  -- 일반 공백 + NBSP + 전각공백(모두 양끝에서 제거)
      ),
      NFC
    )
  );
$$;

REVOKE ALL ON FUNCTION public._normalize_match_text(text) FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.resolve_users_by_identifiers(p_identifiers text[])
RETURNS TABLE (
  matched_identifier text,
  id                  uuid,
  nickname            text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  SELECT raw_app_meta_data->>'role'
  INTO v_caller_role
  FROM auth.users WHERE auth.users.id = auth.uid();

  IF auth.uid() IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '관리자만 실행할 수 있습니다.';
  END IF;

  IF p_identifiers IS NULL OR pg_catalog.array_length(p_identifiers, 1) IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT ident.x AS matched_identifier, sub.id, sub.nickname
  FROM pg_catalog.unnest(p_identifiers) AS ident(x)
  JOIN (
    SELECT
      u.id,
      NULLIF(pg_catalog.btrim(COALESCE(
        u.raw_user_meta_data->>'display_name',
        u.raw_user_meta_data->>'nickname',
        ''
      )), '') AS nickname,
      COALESCE(
        NULLIF(pg_catalog.btrim(u.raw_user_meta_data->>'login_id'), ''),
        pg_catalog.split_part(u.email, '@', 1)
      ) AS login_id
    FROM auth.users u
    WHERE u.deleted_at IS NULL
  ) sub
    ON public._normalize_match_text(ident.x) <> ''
   AND (
     public._normalize_match_text(sub.nickname) = public._normalize_match_text(ident.x)
     OR public._normalize_match_text(sub.login_id) = public._normalize_match_text(ident.x)
   );
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;


-- ════════════════════════════════════════════════════════
-- STEP 2 — 테스트
--
-- 2-A) 헬퍼 함수 단독 테스트(권한 체크 없음 — SQL Editor에서 바로 실행 가능).
--      모든 줄의 normalized 값이 서로 같아야 정상(= 서로 다른 표현이 같은
--      정규화 키로 수렴한다는 뜻).
--
--      "무명(NFD)" 행은 완성형 "무명"을 조합형(자모 분리)으로 직접 풀어쓴
--      것입니다 — 무(U+BB34)=초성ㅁ(U+1106)+중성ㅜ(U+116E, 받침 없음),
--      명(U+BA85)=초성ㅁ(U+1106)+중성ㅕ(U+1167)+종성ㅇ(U+11BC).
-- ════════════════════════════════════════════════════════
SELECT
  '일반 한글 닉네임' AS case_label, '뽀' AS input, public._normalize_match_text('뽀') AS normalized
UNION ALL
SELECT '무명(NFC, 완성형)', U&'\BB34\BA85', public._normalize_match_text(U&'\BB34\BA85')
UNION ALL
SELECT '무명(NFD, 조합형)',
       U&'\1106\116E\1106\1167\11BC',
       public._normalize_match_text(U&'\1106\116E\1106\1167\11BC')
UNION ALL
SELECT '앞뒤 공백 포함 " 무명 "',
       ' ' || U&'\BB34\BA85' || ' ',
       public._normalize_match_text(' ' || U&'\BB34\BA85' || ' ')
UNION ALL
SELECT '전각공백/ZWSP 혼입',
       U&'\3000' || U&'\BB34\BA85' || U&'\200B',
       public._normalize_match_text(U&'\3000' || U&'\BB34\BA85' || U&'\200B');

-- 위 5행 중 "일반 한글 닉네임"(뽀)만 다르고, 나머지 4행(NFC/NFD/공백포함/
-- 전각공백+ZWSP 혼입)의 normalized 값은 전부 서로 동일해야 정상입니다.


-- ════════════════════════════════════════════════════════
-- 2-B) 매칭 로직 자체 확인(권한 체크를 우회한 원시 쿼리 — SQL Editor는
--      postgres 슈퍼유저로 실행되어 auth.uid()가 NULL이라
--      resolve_users_by_identifiers() 자체를 SQL Editor에서 직접 호출하면
--      '관리자만 실행할 수 있습니다' 예외가 그대로 남을 확인해주세요.
--      로직만 따로 검증하려면 아래처럼 같은 매칭 조건을 직접 돌려보면 됩니다.
--      마지막 배열 항목 '뽀'는 기존에 정상 매칭되던 실제 닉네임/아이디로
--      바꿔서 회귀 여부를 확인해주세요. login_id 케이스도 알고 있는 실제
--      login_id 값을 배열에 추가해서 같이 확인해주세요.
--
--      ⚠️ 이 쿼리는 plpgsql 함수 본문을 그대로 실행하는 게 아니라 같은
--      매칭 조건만 재현한 것이라, 이번에 실제로 문제였던
--      "column reference \"id\" is ambiguous"류 plpgsql 전용 오류는 여기서
--      재현되지 않습니다. 이런 문제는 함수를 실제로 호출해야만 드러나므로,
--      아래 SQL 테스트를 통과해도 마지막엔 반드시 실제 화면(예:
--      pages/jellfirella-bulk-transfer.html)에서 "검증하기"를 눌러
--      브라우저 콘솔에 에러가 없는지 함께 확인해주세요.
-- ════════════════════════════════════════════════════════
WITH ident AS (
  SELECT x, public._normalize_match_text(x) AS x_key
  FROM unnest(ARRAY[
    U&'\BB34\BA85',                              -- 무명 (NFC)
    U&'\1106\116E\1106\1167\11BC',                -- 무명 (NFD)
    ' ' || U&'\BB34\BA85' || ' ',                  -- 앞뒤 공백 포함
    '뽀'                                          -- 기존에 정상 매칭되던 유저(회귀 확인용)
  ]) AS x
),
cand AS (
  SELECT
    u.id,
    NULLIF(btrim(COALESCE(u.raw_user_meta_data->>'display_name', u.raw_user_meta_data->>'nickname', '')), '') AS nickname,
    COALESCE(NULLIF(btrim(u.raw_user_meta_data->>'login_id'), ''), split_part(u.email, '@', 1)) AS login_id
  FROM auth.users u
  WHERE u.deleted_at IS NULL
)
SELECT ident.x AS 입력값, cand.id, cand.nickname
FROM ident
JOIN cand
  ON ident.x_key <> ''
 AND (public._normalize_match_text(cand.nickname) = ident.x_key
      OR public._normalize_match_text(cand.login_id) = ident.x_key);

-- 기대 결과: "무명 (NFC)" / "무명 (NFD)" / "앞뒤 공백 포함" 세 행 모두
-- id=5ef47577-744a-4194-af72-d4e4ebfe790a로 매칭되어야 합니다.
-- "뽀" 행도 이전과 동일하게 매칭되는지 확인해서 회귀가 없는지 봐주세요.
