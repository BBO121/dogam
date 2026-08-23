-- ============================================================
-- [기능] 유료분양/경매 등록 제한에 login_id='admin' 계정 전용 예외 추가
-- 작성일: 2026-08-23
-- 수정일: 2026-08-23
--
-- 목적:
--   공식 이벤트 경매 등록을 위해,
--   로그인 아이디가 정확히 'admin'인 계정 1개에 한해서만
--   종족/개체의 allow_paid_adoption=false 제한을 무시하고
--   유료분양/경매를 등록할 수 있도록 한다.
--
-- 중요:
--   - app_metadata.role='admin' 전체 예외가 아니다.
--   - 다른 관리자 계정은 예외 대상이 아니다.
--   - 오직 로그인 아이디가 정확히 'admin'인 계정만 예외다.
--
-- 로그인 아이디 판정:
--   종족연구소 로그인 구조는 입력한 아이디를
--   `${id}@dogam.com` 형태로 변환해서 Supabase Auth email로 사용한다.
--
--   따라서 서버에서는 auth.users.email의 @ 앞부분만 사용해
--   실제 로그인 아이디를 판정한다.
--
--   raw_user_meta_data / user_metadata는 사용하지 않는다.
--   해당 값들은 사용자가 변경할 수 있으므로 권한 판정에 사용하면 안 된다.
--
-- 서버측 검증:
--   adoptions INSERT RLS 정책 "로그인 유저 분양 등록"의
--   paid / auction 분기에만 admin 계정 예외를 추가한다.
--
--   기존:
--   - 종족주 예외
--   - 캐릭터 소유권 검증
--   - 재분양 허용 여부
--   - 무료분양
--   - 기타분양
--   - 디자인권(슬롯) 분양
--
--   로직은 그대로 유지한다.
-- ============================================================



-- ================================================================
-- 1. 현재 로그인 아이디 조회 함수
-- ================================================================

CREATE OR REPLACE FUNCTION public.current_user_login_id()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $$
  SELECT split_part(u.email, '@', 1)
  FROM auth.users u
  WHERE u.id = auth.uid();
$$;

COMMENT ON FUNCTION public.current_user_login_id() IS
'현재 요청자(auth.uid())의 로그인 아이디를 auth.users.email의 @ 앞부분에서 반환한다. 종족연구소의 id@dogam.com 로그인 구조를 기준으로 하는 서버측 신뢰 판별용 함수이며 raw_user_meta_data/user_metadata는 사용하지 않는다.';

REVOKE ALL
ON FUNCTION public.current_user_login_id()
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.current_user_login_id()
TO authenticated;



-- ================================================================
-- 2. 프론트 사전검증용 boolean 함수
-- ================================================================
-- login_id 원문 자체를 프론트에 넘길 필요 없이
-- 현재 사용자가 admin 로그인 계정인지 여부만 반환한다.
--
-- 이 RPC는 UI 사전검증용일 뿐이며,
-- 실제 권한 강제는 아래 adoptions INSERT RLS가 담당한다.
-- ================================================================

CREATE OR REPLACE FUNCTION public.is_admin_login_id_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $$
  SELECT public.current_user_login_id() = 'admin';
$$;

COMMENT ON FUNCTION public.is_admin_login_id_user() IS
'현재 요청자의 실제 로그인 아이디(auth.users.email의 @ 앞부분)가 정확히 admin인지 반환한다. 유료분양/경매 등록 화면의 사전검증용이며 실제 서버 권한 검증은 adoptions INSERT RLS가 담당한다.';

REVOKE ALL
ON FUNCTION public.is_admin_login_id_user()
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.is_admin_login_id_user()
TO authenticated;



-- ================================================================
-- 3. adoptions INSERT RLS 정책 수정
-- ================================================================
-- 원본:
-- supabase/adoption_rule_species_owner_exception_0822.sql
--
-- 변경 범위:
--   adoption_type='paid'
--   adoption_type='auction'
--
-- 위 두 분기에만
-- OR public.current_user_login_id() = 'admin'
-- 을 추가한다.
-- ================================================================

BEGIN;

DROP POLICY IF EXISTS "로그인 유저 분양 등록"
ON public.adoptions;


CREATE POLICY "로그인 유저 분양 등록"
ON public.adoptions
FOR INSERT
TO authenticated
WITH CHECK (

  -- ------------------------------------------------------------
  -- 작성자 신원 검증
  -- ------------------------------------------------------------

  user_id = auth.uid()

  AND author = COALESCE(
    NULLIF(
      (auth.jwt() -> 'user_metadata'::text) ->> 'display_name'::text,
      ''::text
    ),
    (auth.jwt() -> 'user_metadata'::text) ->> 'nickname'::text
  )


  -- ------------------------------------------------------------
  -- adoption_type 공통 유효성 검증
  -- ------------------------------------------------------------

  AND adoption_type IN (
    'free',
    'paid',
    'auction',
    'etc'
  )


  AND (

    -- ==========================================================
    -- 1. 캐릭터 분양
    -- ==========================================================

    (
      character_id IS NOT NULL
      AND slot_id IS NULL

      AND EXISTS (

        SELECT 1

        FROM public.characters c

        LEFT JOIN public.species sp
          ON sp.name = c.species_name

        WHERE c.id = adoptions.character_id


          -- 반드시 본인 소유 개체
          AND c.owner_user_id = auth.uid()


          AND (

            -- --------------------------------------------------
            -- 종족주 본인은 기존대로 분양 규칙 예외
            -- --------------------------------------------------

            (
              sp.owner_user_id IS NOT NULL
              AND sp.owner_user_id = auth.uid()
            )


            OR


            -- --------------------------------------------------
            -- 일반 사용자 분양 규칙
            -- --------------------------------------------------

            (

              -- 재분양 자체가 허용되어 있어야 함
              COALESCE(
                c.allow_resale,
                sp.allow_resale,
                true
              )


              AND CASE adoptions.adoption_type


                -- ==================================================
                -- 무료분양
                -- ==================================================

                WHEN 'free' THEN

                  COALESCE(
                    c.allow_free_adoption,
                    sp.allow_free_adoption,
                    true
                  )


                -- ==================================================
                -- 유료분양
                -- ==================================================
                -- login_id='admin' 계정만 allow_paid_adoption 제한 예외
                -- ==================================================

                WHEN 'paid' THEN

                  (
                    COALESCE(
                      c.allow_paid_adoption,
                      sp.allow_paid_adoption,
                      true
                    )

                    OR public.current_user_login_id() = 'admin'
                  )


                -- ==================================================
                -- 경매
                -- ==================================================
                -- login_id='admin' 계정만 allow_paid_adoption 제한 예외
                -- ==================================================

                WHEN 'auction' THEN

                  (
                    COALESCE(
                      c.allow_paid_adoption,
                      sp.allow_paid_adoption,
                      true
                    )

                    OR public.current_user_login_id() = 'admin'
                  )


                -- ==================================================
                -- 기타분양
                -- ==================================================

                WHEN 'etc' THEN

                  COALESCE(
                    c.allow_other_adoption,
                    sp.allow_other_adoption,
                    true
                  )


                ELSE false

              END

            )

          )

      )

    )


    OR


    -- ==========================================================
    -- 2. 디자인권(슬롯) 분양
    -- 기존 로직 그대로 유지
    -- ==========================================================

    (
      character_id IS NULL
      AND slot_id IS NOT NULL

      AND EXISTS (

        SELECT 1

        FROM public.slots sl

        JOIN public.species sp
          ON sp.id = sl.species_id

        WHERE sl.id = adoptions.slot_id
          AND sp.owner_user_id = auth.uid()

      )

    )

  )

);

COMMIT;



-- ================================================================
-- 4. 적용 확인
-- ================================================================

SELECT
  proname,
  prosecdef
FROM pg_proc
WHERE proname IN (
  'current_user_login_id',
  'is_admin_login_id_user'
)
AND pronamespace = 'public'::regnamespace;


SELECT
  polname,
  polcmd,
  polroles::regrole[]
FROM pg_policy
WHERE polrelid = 'public.adoptions'::regclass
  AND polname = '로그인 유저 분양 등록';



-- ================================================================
-- 5. 테스트
-- ================================================================
--
-- 주의:
-- Supabase SQL Editor에서는 auth.uid()가 없기 때문에
-- 아래 함수를 직접 실행하면 NULL / false가 나오는 것이 정상이다.
--
-- 실제 로그인 사용자 판정은 사이트 콘솔 또는 프론트에서 RPC로 테스트한다.
--
--
-- [admin 계정 로그인 상태]
--
-- const { data, error } = await sb.rpc('current_user_login_id');
-- console.log(data, error);
--
-- 기대값:
-- admin
--
--
-- const { data, error } = await sb.rpc('is_admin_login_id_user');
-- console.log(data, error);
--
-- 기대값:
-- true
--
--
-- [다른 계정 로그인 상태]
--
-- 기대:
-- current_user_login_id() → 해당 아이디
-- is_admin_login_id_user() → false
--
--
-- 기능 테스트:
--
-- 1) login_id='admin'
--    + allow_paid_adoption=false 개체
--    + 유료분양 등록
--    → 성공
--
-- 2) login_id='admin'
--    + allow_paid_adoption=false 개체
--    + 경매 등록
--    → 성공
--
-- 3) 다른 관리자/일반 사용자
--    + allow_paid_adoption=false 개체
--    + 유료분양/경매
--    → 기존처럼 차단
--
-- 4) 일반 사용자가 user_metadata 또는 raw_user_meta_data에
--    login_id='admin'을 넣더라도
--    → 아무 효과 없어야 함
--
-- 5) 종족주 본인이 자기 종족 개체 등록
--    → 기존 종족주 예외 그대로 정상 동작
--
-- 6) 무료분양/기타분양/슬롯분양
--    → 기존 동작 그대로 유지
-- ================================================================