-- ============================================
-- 종족 상점 아이템 10종 추가
-- 프레임(종족) 5종: 옥토몬스터 / 쁘띠아라크네 / 뜨개뽀기 / 비홀로틀 / 버블리
--   (연구기록 100 + 열쇠 1, 이중 통화 — 기존 종족 프레임과 동일)
-- 스티커(종족) 5종: 위 5종 각 1개
--   (연구기록 100 — 기존 종족 스티커와 동일)
-- species_link_id: 85(옥토몬스터) / 86(쁘띠아라크네) / 6(뜨개뽀기) / 36(비홀로틀) / 68(버블리)
-- 작성일: 2026-08-15
-- ============================================

-- ── 1. 프레임 · 종족: 옥토몬스터 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '옥토몬스터(Octomonster)', '수상한 우주의 옥몬',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_octomonster.png', 'frame-sp-octomonster', '종족', '이상어', 172, '85'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-octomonster'
);

-- ── 2. 프레임 · 종족: 쁘띠아라크네 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '쁘띠아라크네(Petit Arachne)', '당신의 꿈을 가지러 왔쮸',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_petitarachne.png', 'frame-sp-petitarachne', '종족', '이상어', 173, '86'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-petitarachne'
);

-- ── 3. 프레임 · 종족: 뜨개뽀기 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '뜨개뽀기', '뜨개뽀기들아 실을 다 풀면 어떡해!',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_bbogi.png', 'frame-sp-bbogi', '종족', '뽀', 174, '6'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-bbogi'
);

-- ── 4. 프레임 · 종족: 비홀로틀 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '비홀로틀', '비홀로틀과 함께 잠수하기! 단돈...',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_Bexolotl.png', 'frame-sp-bexolotl', '종족', '냐수', 175, '36'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-bexolotl'
);

-- ── 5. 프레임 · 종족: 버블리 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, secondary_currency, secondary_price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'frame', '버블리', '버블리 체험 츄라이 츄라이',
  'research_records', 100, 'keys', 1, 'active',
  '../images/shop/frame_sp_bubblere.png', 'frame-sp-bubblere', '종족', '율하', 176, '68'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-sp-bubblere'
);

-- ── 6. 스티커 · 종족: 옥토몬스터 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '옥토몬스터(Octomonster)', '옥몬이가 둥실',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_octomonster.png', 'sticker-sp-octomonster', '종족', '이상어', 190, '85'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-octomonster'
);

-- ── 7. 스티커 · 종족: 쁘띠아라크네 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '쁘띠아라크네(Petit Arachne)', '쁘아가 두둥실',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_petitarachne.png', 'sticker-sp-petitarachne', '종족', '이상어', 200, '86'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-petitarachne'
);

-- ── 8. 스티커 · 종족: 뜨개뽀기 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '뜨개뽀기', '내 뽀기가 어디갔지? 아, 머리위에!',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_bbogi.png', 'sticker-sp-bbogi', '종족', '뽀', 210, '6'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-bbogi'
);

-- ── 9. 스티커 · 종족: 비홀로틀 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '비홀로틀', '물 속에서 숨을 못 쉬는 당신에게 꼭 필요한 것',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_Bexolotl.png', 'sticker-sp-bexolotl', '종족', '냐수', 220, '36'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-bexolotl'
);

-- ── 10. 스티커 · 종족: 버블리 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order, species_link_id)
SELECT
  'sticker', '버블리', '누구의 장난감일까?',
  'research_records', 100, 'active',
  '../images/shop/sticker_sp_bubblere.png', 'sticker-sp-bubblere', '종족', '율하', 230, '68'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-sp-bubblere'
);
