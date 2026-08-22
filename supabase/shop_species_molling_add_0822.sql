-- ============================================
-- 몰링(Molling) 종족 상점 아이템 2종 추가
-- 프레임(종족) 1종: 몰링 (연구기록 100 + 열쇠 1, 이중 통화 — 기존 종족 프레임과 동일)
-- 스티커(종족) 1종: 몰링 (연구기록 100 — 기존 종족 스티커와 동일)
-- species_link_id: 185 (species.html?id=185)
-- 종족주(디자인 바이): 캐로로캐
-- sort_order: 프레임 177(기존 176 버블리 다음) / 스티커 240(기존 230 버블리 다음)
-- 작성일: 2026-08-22
-- ============================================

-- ── 1. 프레임 · 종족: 몰링 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '몰링(Molling)', '백화점에 어서와!',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_molling.png', 'frame-sp-molling', '종족', '캐로로캐', 177, '185'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-molling'
);

-- ── 2. 스티커 · 종족: 몰링 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '몰링(Molling)', '무엇을 사고싶니?',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_molling.png', 'sticker-sp-molling', '종족', '캐로로캐', 240, '185'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-molling'
);

-- ── 확인용 (읽기 전용) ──────────────────
SELECT id, item_type, name, style_key, sort_order, species_link_id, credit
FROM public.shop_items
WHERE style_key IN ('frame-sp-molling', 'sticker-sp-molling')
ORDER BY item_type;
