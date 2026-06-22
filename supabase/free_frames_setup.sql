-- ============================================
-- 공오민트 / 공오오렌지 가격 0(무료) 변경
-- 작성일: 2026-06-22
-- ============================================

-- ── 1. price CHECK 제약 변경 (0 허용) ──

ALTER TABLE public.shop_items
DROP CONSTRAINT shop_items_price_check;

ALTER TABLE public.shop_items
ADD CONSTRAINT shop_items_price_check
CHECK (price >= 0);

-- ── 2. 가격 0으로 변경 ──

UPDATE public.shop_items
SET price = 0
WHERE style_key IN ('frame-mint', 'frame-orange');

-- ── 3. 확인 ──

SELECT name, price, style_key
FROM public.shop_items
WHERE style_key IN ('frame-mint', 'frame-orange');
