-- ============================================
-- 가입 보너스 100 → 30 조정
-- 작성일: 2026-06-21
-- 실행 순서: 1 → 2 → 3 → 4
-- ============================================

-- ── 1. 신규 가입자 트리거 함수 수정 ─────────────
--  앞으로 가입하는 유저부터 +30 지급

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


-- ── 2. 기존 signup_bonus 로그 수정 ──────────────
--  amount / balance_after 100 → 30 으로 직접 수정

UPDATE public.currency_logs
SET
  amount        = 30,
  balance_after = 30
WHERE type     = 'signup_bonus'
  AND source   = 'signup'
  AND currency = 'research_records';


-- ── 3. 후속 연구기록 로그 balance_after 보정 ──────
--  signup_bonus 이후에 발생한 research_records 로그의
--  balance_after 를 70 차감하여 거래내역 흐름 일치
--
--  조건:
--  - signup_bonus 대상 유저만
--  - currency = 'research_records'
--  - signup_bonus 본인 로그 제외 (type != 'signup_bonus')
--  - signup_bonus 발생 시각 이후 로그만 (created_at > signup_at)
--  - balance_after >= 70 인 경우만 (음수 방지)

UPDATE public.currency_logs cl
SET balance_after = cl.balance_after - 70
FROM (
  SELECT user_id, created_at AS signup_at
  FROM public.currency_logs
  WHERE type     = 'signup_bonus'
    AND source   = 'signup'
    AND currency = 'research_records'
) signup
WHERE cl.user_id       = signup.user_id
  AND cl.currency      = 'research_records'
  AND cl.type         != 'signup_bonus'
  AND cl.created_at    > signup.signup_at
  AND cl.balance_after >= 70;


-- ── 4. 기존 유저 지갑 보정 ───────────────────────
--  가입 보너스 차액(70)만 차감
--  출석 보상 등 이후 획득 재화 유지
--  음수 방지 GREATEST(0, ...) 포함

UPDATE public.user_wallets w
SET
  research_records = GREATEST(0, research_records - 70),
  updated_at       = now()
WHERE EXISTS (
  SELECT 1
  FROM public.currency_logs cl
  WHERE cl.user_id  = w.user_id
    AND cl.type     = 'signup_bonus'
    AND cl.source   = 'signup'
    AND cl.currency = 'research_records'
);


-- ── 실행 후 확인 쿼리 ────────────────────────────

-- 거래내역 흐름 확인 (유저별 research_records 로그 순서대로)
-- SELECT user_id, type, amount, balance_after, created_at
-- FROM public.currency_logs
-- WHERE currency = 'research_records'
-- ORDER BY user_id, created_at;

-- 지갑 잔액 확인
-- SELECT user_id, research_records, keys
-- FROM public.user_wallets
-- ORDER BY user_id;
