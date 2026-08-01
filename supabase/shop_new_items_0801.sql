-- ============================================
-- 신규 상점 아이템 6종 추가
-- 프레임(일러스트) 1종: 게롱
-- 스티커(일러스트) 4종: 물고기 / 종족오타쿠 / 스타메달 / 하트메달
-- 스티커(한정) 1종: 2026
-- 작성일: 2026-08-01
-- ============================================

-- ── 1. 프레임 · 일러스트: 게롱 ──────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'frame', '게롱', '게롱게롱게롱게롱',
  'research_records', 100, 'active',
  '../images/shop/frame_ai_gerong.png', 'frame-ai-gerong', '일러스트', '모로', 168
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-ai-gerong'
);

-- ── 2. 스티커 · 일러스트: 물고기 ────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'sticker', '물고기', '첨벙! X1000',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_fish.png', 'sticker-ai-fish', '일러스트', '모로', 90
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-ai-fish'
);

-- ── 3. 스티커 · 일러스트: 종족오타쿠 ────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'sticker', '종족오타쿠', '이거 보고 있는 당신이요!',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_otaku.png', 'sticker-ai-otaku', '일러스트', '모로', 100
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-ai-otaku'
);

-- ── 4. 스티커 · 일러스트: 스타메달 ──────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'sticker', '스타메달', '언제나 항상 별처럼 빛나시는군요!',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_starmedal.png', 'sticker-ai-starmedal', '일러스트', '모로', 110
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-ai-starmedal'
);

-- ── 5. 스티커 · 일러스트: 하트메달 ──────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'sticker', '하트메달', '언제나 항상 사랑이 넘치시는군요!',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_heartmedal.png', 'sticker-ai-heartmedal', '일러스트', '모로', 120
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-ai-heartmedal'
);

-- ── 6. 스티커 · 한정: 2026 ──────────────────────
-- 판매 종료 의도: 2026-12-31 23:59(:59)까지 구매 가능
-- purchase_item / 목록조회 쿼리 모두 "sale_end_at 미만"까지만 허용하므로
-- 23:59분대 전체를 포함하도록 다음날 00:00(2027-01-01 00:00:00+09)으로 저장
-- (frame-li-bbo에 적용된 것과 동일한 방식 — sale_end_at_setup.sql 참고)
-- 상세 모달에는 (sale_end_at - 1ms) 기준으로 "2026년 12월 31일까지"로 표시됨
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, sort_order, sale_end_at)
SELECT
  'sticker', '2026', '얼마 안남았지만 기분이라도 내줘!',
  'research_records', 20, 'active',
  '../images/shop/sticker_li_2026.png', 'sticker-li-2026', '한정', 200, '2027-01-01 00:00:00+09'
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'sticker-li-2026'
);
