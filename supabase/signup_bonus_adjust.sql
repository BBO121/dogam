-- ============================================
-- 가입 보너스 100 → 30 조정
-- 작성일: 2026-06-21
-- 수정일: 2026-06-21 (재실행 안전성 강화)
--
-- 재실행 안전 보장:
--   2~4번은 단일 CTE 블록으로 처리
--   target_users = "amount=100, balance_after=100인 signup_bonus 로그를 가진 유저"
--   이미 적용된 경우 target_users가 빈 집합 → 아무것도 변경되지 않음
-- ============================================


-- ── 1. 신규 가입자 트리거 함수 수정 ─────────────
--  CREATE OR REPLACE 이므로 재실행 항상 안전

CREATE OR REPLACE FUNCTION public.handle_new_user_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_wallets (user_id, research_records, keys)
  VALUES (NEW.id, 30, 0);

  INSERT INTO public.currency_logs
    (user_id, type, source, currency, amount, balance_after, note)
  VALUES
    (NEW.id, 'signup_bonus', 'signup', 'research_records', 30, 30, '가입을 환영합니다!');

  RETURN NEW;
END;
$$;


-- ── 2~4. 기존 데이터 보정 (단일 CTE 블록, 재실행 안전) ──
--
--  target_users:
--    amount=100, balance_after=100 인 signup_bonus 로그를 보유한 유저
--    → 이미 보정된 유저는 조건 불일치로 포함되지 않음
--
--  fix_signup_log   (2번): signup_bonus 로그 amount/balance_after 100→30
--  fix_subsequent   (3번): 이후 research_records 로그 balance_after -70
--  최종 UPDATE      (4번): user_wallets research_records -70

WITH target_users AS (
  SELECT user_id, created_at AS signup_at
  FROM public.currency_logs
  WHERE type          = 'signup_bonus'
    AND source        = 'signup'
    AND currency      = 'research_records'
    AND amount        = 100          -- 아직 보정 안 된 로그만
    AND balance_after = 100
),
fix_signup_log AS (
  UPDATE public.currency_logs
  SET
    amount        = 30,
    balance_after = 30
  WHERE type          = 'signup_bonus'
    AND source        = 'signup'
    AND currency      = 'research_records'
    AND amount        = 100
    AND balance_after = 100
  RETURNING user_id
),
fix_subsequent AS (
  UPDATE public.currency_logs cl
  SET balance_after = cl.balance_after - 70
  FROM target_users tu
  WHERE cl.user_id       = tu.user_id
    AND cl.currency      = 'research_records'
    AND cl.type         != 'signup_bonus'
    AND cl.created_at    > tu.signup_at
    AND cl.balance_after >= 70          -- 음수 방지
  RETURNING cl.user_id
)
UPDATE public.user_wallets w
SET
  research_records = GREATEST(0, research_records - 70),
  updated_at       = now()
FROM target_users tu
WHERE w.user_id = tu.user_id;


-- ── 실행 후 확인 쿼리 ────────────────────────────

-- 거래내역 흐름 확인 (유저별 research_records 로그 순서)
-- SELECT user_id, type, amount, balance_after, created_at
-- FROM public.currency_logs
-- WHERE currency = 'research_records'
-- ORDER BY user_id, created_at;

-- 지갑 잔액 확인
-- SELECT user_id, research_records, keys, updated_at
-- FROM public.user_wallets
-- ORDER BY user_id;
