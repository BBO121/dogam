-- ============================================
-- 공오민트 / 공오오렌지 가격 0(무료) 변경
-- 작성일: 2026-06-22
-- ============================================

-- ── 1. price CHECK 제약 조건 완화 (0 허용) ──
--    기존 제약(price > 0)이 있을 경우 동적으로 제거 후 재설정
DO $$
DECLARE
  con_name text;
BEGIN
  SELECT conname INTO con_name
  FROM pg_constraint
  WHERE conrelid = 'public.shop_items'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%price%';

  IF con_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.shop_items DROP CONSTRAINT ' || quote_ident(con_name);
  END IF;
END $$;

ALTER TABLE public.shop_items
ADD CONSTRAINT shop_items_price_check CHECK (price >= 0);

-- ── 2. 가격 0으로 변경 ──
UPDATE public.shop_items
SET price = 0
WHERE style_key IN ('frame-mint', 'frame-orange');
