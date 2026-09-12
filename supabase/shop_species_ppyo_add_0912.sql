-- ============================================
-- 뾰둥이(PPYO) 종족 상점 아이템 2종 추가
-- 프레임(종족) 1종: 뾰둥이(PPYO) (연구기록 100 + 열쇠 1, 이중 통화 — 기존 종족 프레임과 동일)
-- 스티커(종족) 1종: 뾰둥이(PPYO) (연구기록 100 — 기존 종족 스티커와 동일)
-- species_link_id: 166 (species.html?id=166)
-- 종족주(디자인 바이): 달차비
-- sort_order: 프레임 178(기존 177 몰링 다음) / 스티커 250(기존 240 몰링 다음)
-- 작성일: 2026-09-12
-- ============================================

-- ── 1. 프레임 · 종족: 뾰둥이(PPYO) ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '뾰둥이(PPYO)', '힘들면 우리 품에서 쉬어가도 좋아',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_ppyo.png', 'frame-sp-ppyo', '종족', '달차비', 178, '166'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-ppyo'
);

-- ── 2. 스티커 · 종족: 뾰둥이(PPYO) ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '뾰둥이(PPYO)', '솜털티끌언덕으로 가자~',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_ppyo.png', 'sticker-sp-ppyo', '종족', '달차비', 250, '166'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-ppyo'
);

-- ── 확인용 (읽기 전용) ──────────────────
SELECT id, item_type, name, style_key, sort_order, species_link_id, credit
FROM public.shop_items
WHERE style_key IN ('frame-sp-ppyo', 'sticker-sp-ppyo')
ORDER BY item_type;
