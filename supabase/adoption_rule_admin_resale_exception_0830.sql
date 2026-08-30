-- ============================================================
-- [기능] 재분양(allow_resale) 제한에도 login_id='admin' 계정 예외 추가
-- 작성일: 2026-08-30
--
-- 배경:
--   supabase/adoption_rule_admin_login_id_exception_0823.sql에서
--   유료분양(paid)/경매(auction)의 allow_paid_adoption 제한에만
--   login_id='admin' 예외를 추가했었다.
--
--   그런데 allow_resale(재분양 자체 허용 여부) 체크는 그 CASE 문
--   바깥에서 모든 분양 유형(free/paid/auction/etc) 공통으로 먼저
--   걸리는 게이트라, admin 계정이라도 allow_resale=false인 개체는
--   여전히 등록이 막혀 있었다(프론트: pages/adoption-write.html
--   '재분양 불가능 개체입니다!').
--
--   공식 이벤트(프리미엄/최상단 고정 분양 등) 등록 목적의 admin 계정은
--   allow_paid_adoption과 마찬가지로 allow_resale 제한도 예외로 두어야
--   하므로, 동일한 login_id='admin' 판정으로 확장한다.
--
-- 중요:
--   - app_metadata.role='admin' 전체 예외가 아니다.
--   - 오직 로그인 아이디가 정확히 'admin'인 계정만 예외다(기존과 동일).
--   - 종족주 예외 / allow_free_adoption / allow_other_adoption /
--     디자인권(슬롯) 분양 로직은 그대로 유지한다.
--
-- 변경 범위:
--   adoptions INSERT RLS 정책 "로그인 유저 분양 등록"에서
--   COALESCE(c.allow_resale, sp.allow_resale, true) 게이트에만
--   OR public.current_user_login_id() = 'admin' 을 추가한다.
--   (원본 정의는 supabase/adoption_rule_admin_login_id_exception_0823.sql)
-- ============================================================


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
              -- login_id='admin' 계정만 이 게이트도 예외
              (
                COALESCE(
                  c.allow_resale,
                  sp.allow_resale,
                  true
                )

                OR public.current_user_login_id() = 'admin'
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
-- 적용 확인
-- ================================================================

SELECT
  polname,
  polcmd,
  polroles::regrole[]
FROM pg_policy
WHERE polrelid = 'public.adoptions'::regclass
  AND polname = '로그인 유저 분양 등록';



-- ================================================================
-- 테스트
-- ================================================================
--
-- 1) login_id='admin'
--    + allow_resale=false 개체
--    + 유료분양/경매/무료분양/기타분양 등록
--    → 성공 (신규)
--
-- 2) login_id='admin'
--    + allow_paid_adoption=false, allow_resale=true 개체
--    + 유료분양/경매 등록
--    → 성공 (기존 0823 예외 그대로 유지)
--
-- 3) 다른 관리자/일반 사용자
--    + allow_resale=false 개체
--    → 기존처럼 차단
--
-- 4) 종족주 본인이 자기 종족 개체 등록
--    → 기존 종족주 예외 그대로 정상 동작
-- ================================================================
