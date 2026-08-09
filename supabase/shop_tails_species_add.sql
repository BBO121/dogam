-- ============================================
-- 테일스 종족 상점 아이템 3종 추가
-- 프레임(종족) 1종: 테일스 (연구기록 100 + 열쇠 1, 이중 통화)
-- 스티커(종족) 2종: 테일스1 / 테일스2 (연구기록 100)
-- species_link_id = '169' (species.html?id=169)
-- 작성일: 2026-08-09
-- ============================================

-- ── 1. 프레임 · 종족: 테일스 ──────────────────
INSERT INTO public.shop_items
  (
    item_type,
    name,
    description,
    currency,
    price,
    secondary_currency,
    secondary_price,
    status,
    image_url,
    style_key,
    sub_category,
    credit,
    sort_order,
    species_link_id
  )
SELECT
  'frame',
  '테일스',
  '테일스에게 먹혀봐요. 와굿!',
  'research_records',
  100,
  'keys',
  1,
  'active',
  '../images/shop/frame_sp_tails.png',
  'frame-sp-tails',
  '종족',
  '슷큐',
  170,
  '169'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-tails'
);

-- ── 2. 스티커 · 종족: 테일스1 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '테일스1', '에니스가 되어봐요',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_tails1.png', 'sticker-sp-tails1', '종족', '슷큐', 170, '169'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-tails1'
);

-- ── 3. 스티커 · 종족: 테일스2 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '테일스2', '데비스가 되어봐요',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_tails2.png', 'sticker-sp-tails2', '종족', '슷큐', 180, '169'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-tails2'
);
