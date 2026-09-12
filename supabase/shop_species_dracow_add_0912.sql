-- ============================================
-- 드라카우(Dracow) 종족 상점 아이템 4종 추가
-- 프레임(종족) 2종: 드라카우1(Dracow) / 드라카우2(Dracow) (연구기록 100 + 열쇠 1, 이중 통화 — 기존 종족 프레임과 동일)
-- 스티커(종족) 2종: 드라카우1(Dracow) / 드라카우2(Dracow) (연구기록 100 — 기존 종족 스티커와 동일)
-- species_link_id: 79 (species.html?id=79)
-- 종족주(디자인 바이): 유공
-- sort_order: 프레임 179~180(기존 178 뾰둥이 다음) / 스티커 251~252(기존 250 뾰둥이 다음)
-- 작성일: 2026-09-12
-- ============================================

-- ── 1. 프레임 · 종족: 드라카우1(Dracow) ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '드라카우1(Dracow)', '드라카우는 드래곤이라우',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_dracow1.png', 'frame-sp-dracow1', '종족', '유공', 179, '79'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-dracow1'
);

-- ── 2. 프레임 · 종족: 드라카우2(Dracow) ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '드라카우2(Dracow)', '드라카우는 날개가 많다우',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_dracow2.png', 'frame-sp-dracow2', '종족', '유공', 180, '79'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-dracow2'
);

-- ── 3. 스티커 · 종족: 드라카우1(Dracow) ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '드라카우1(Dracow)', '드라카우는 당신을 사랑한다우',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_dracow1.png', 'sticker-sp-dracow1', '종족', '유공', 251, '79'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-dracow1'
);

-- ── 4. 스티커 · 종족: 드라카우2(Dracow) ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '드라카우2(Dracow)', '... ... . (드라카우의 심장이 당신을 수호합니다)',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_dracow2.png', 'sticker-sp-dracow2', '종족', '유공', 252, '79'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-dracow2'
);

-- ── 확인용 (읽기 전용) ──────────────────
SELECT id, item_type, name, style_key, sort_order, species_link_id, credit
FROM public.shop_items
WHERE style_key IN ('frame-sp-dracow1', 'frame-sp-dracow2', 'sticker-sp-dracow1', 'sticker-sp-dracow2')
ORDER BY item_type, style_key;
