-- ============================================
-- currency_logs.amount 제약 완화 (0 허용)
-- 작성일: 2026-06-22
-- 원인: 무료 상품(price=0) 구매 시 amount=0 로그 INSERT 실패
-- ============================================

-- ── 1. 기존 amount 체크 제약 제거 ──
DO $$
DECLARE
  con_name text;
BEGIN
  SELECT conname INTO con_name
  FROM pg_constraint
  WHERE conrelid = 'public.currency_logs'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%amount%';

  IF con_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.currency_logs DROP CONSTRAINT ' || quote_ident(con_name);
  END IF;
END $$;

-- ── 2. amount >= 0 으로 재설정 ──
ALTER TABLE public.currency_logs
ADD CONSTRAINT currency_logs_amount_check CHECK (amount >= 0);
