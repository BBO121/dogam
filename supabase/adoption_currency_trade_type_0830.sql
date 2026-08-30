-- ============================================================
-- [기능] 분양 유형 "재화거래(currency)" 추가
-- 작성일: 2026-08-30
--
-- 배경:
--   유료(paid) 분양과 동일한 흐름이지만, 현금 가격 대신 사이트 내부
--   재화(연구기록/열쇠)를 거래 조건으로 기록하는 분양 유형을 추가한다.
--   기존 price 컬럼(텍스트, 현금가 문자열 그대로 표시)에 재화 값을
--   억지로 끼워넣지 않고, auction_details.auction_currency /
--   shop_items.secondary_currency와 동일한 패턴으로 전용 컬럼을 둔다.
--
-- 중요 — 이 기능은 재화 자동 차감/지급을 하지 않는다:
--   분양 등록 시 "거래 조건이 재화임"을 기록/표시만 하고,
--   user_wallets/currency_logs는 절대 건드리지 않는다. 실제 재화
--   이동은 기존 재화 전송 기능(마이월렛)으로 판매자·구매자가 직접
--   처리한 뒤, 판매자가 분양확정을 누르는 방식이다.
--
-- 변경 사항:
--   1) adoptions.currency_type / currency_amount 컬럼 추가
--   2) INSERT RLS 정책 "로그인 유저 분양 등록"에 adoption_type='currency'
--      허용 추가 — 권한 게이트는 paid와 동일(allow_paid_adoption,
--      login_id='admin' 예외 포함). allow_resale 게이트는 공통이라
--      자동으로 적용됨.
--   (원본 정의는 supabase/adoption_rule_admin_resale_exception_0830.sql)
-- ============================================================

BEGIN;

-- ── 1. 컬럼 추가 ─────────────────────────────
ALTER TABLE public.adoptions
  ADD COLUMN IF NOT EXISTS currency_type   text,
  ADD COLUMN IF NOT EXISTS currency_amount integer;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'adoptions_currency_type_check'
  ) THEN
    ALTER TABLE public.adoptions
      ADD CONSTRAINT adoptions_currency_type_check
      CHECK (currency_type IS NULL OR currency_type IN ('research_records', 'keys'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'adoptions_currency_amount_check'
  ) THEN
    ALTER TABLE public.adoptions
      ADD CONSTRAINT adoptions_currency_amount_check
      CHECK (currency_amount IS NULL OR currency_amount > 0);
  END IF;
END $$;

COMMENT ON COLUMN public.adoptions.currency_type IS
'adoption_type=''currency''(재화거래) 전용. 거래 조건으로 사용하는 사이트 재화 종류 — research_records(연구기록) 또는 keys(열쇠). 자동 차감/지급 없음, 표시/기록 용도만.';
COMMENT ON COLUMN public.adoptions.currency_amount IS
'adoption_type=''currency''(재화거래) 전용. currency_type 재화의 거래 수량(1 이상 정수). 자동 차감/지급 없음, 표시/기록 용도만.';


-- ── 2. INSERT RLS 정책 재생성 — adoption_type='currency' 허용 ──
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
    'etc',
    'currency'
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
                -- 재화거래
                -- 유료분양과 동일한 권한 게이트(allow_paid_adoption)를
                -- 공유한다 — 현금 대신 사이트 재화를 조건으로 쓸 뿐,
                -- "유료성 분양"이라는 성격은 동일하기 때문.
                -- login_id='admin' 계정만 allow_paid_adoption 제한 예외
                -- ==================================================

                WHEN 'currency' THEN

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

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'adoptions'
  AND column_name IN ('currency_type', 'currency_amount');


-- ================================================================
-- 테스트
-- ================================================================
--
-- 1) allow_paid_adoption=true 개체 + 재화거래(currency) 등록
--    → 성공
--
-- 2) allow_paid_adoption=false 개체 + 일반 사용자 + 재화거래 등록
--    → 차단 (기존 유료분양과 동일하게 막혀야 함)
--
-- 3) login_id='admin' 계정 + allow_paid_adoption=false 개체 + 재화거래 등록
--    → 성공 (paid/auction과 동일한 예외)
--
-- 4) currency_type을 'research_records'/'keys' 외 값으로 INSERT/UPDATE
--    → CHECK 제약 위반으로 거부
--
-- 5) currency_amount를 0 또는 음수로 INSERT/UPDATE
--    → CHECK 제약 위반으로 거부
--
-- 6) 기존 유료(paid)/무료(free)/경매(auction)/기타(etc) 분양 등록
--    → 기존과 동일하게 정상 동작 (회귀 없음)
-- ================================================================
