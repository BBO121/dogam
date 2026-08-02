-- ============================================
-- 스티커 신규 2종 추가 (메어나이트1 / 메어나이트2)
-- 종족: 종족 스티커는 일러스트 스티커와 별도 가격 정책 사용 (연구기록 100)
-- 작성일: 2026-08-02
-- ============================================

-- ── 1. 스티커 · 종족: 메어나이트1 ────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'sticker', '메어나이트1', '심연과...',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_marenight1.png', 'sticker-sp-marenight1', '종족', 'MS', 150
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-marenight1'
);

-- ── 2. 스티커 · 종족: 메어나이트2 ────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'sticker', '메어나이트2', '좌절이...',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_marenight2.png', 'sticker-sp-marenight2', '종족', 'MS', 160
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-marenight2'
);
