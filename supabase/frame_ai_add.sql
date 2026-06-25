-- ============================================
-- 일러스트 프레임 7종 + 한정 프레임 1종 추가
-- 작성일: 2026-06-25
-- ============================================

-- ── 일러스트 프레임 7종 ──────────────────────
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
VALUES
  ('frame', '공룡',       '너희도 멸종되지 않게 조심해',     'research_records', 80, 'active', '../images/shop/frame_ai_dino.png',     'frame-ai-dino',     '일러스트', '냐수', 100),
  ('frame', '달밤',       '별이 빛나는 밤에',                 'research_records', 80, 'active', '../images/shop/frame_ai_night.png',    'frame-ai-night',    '일러스트', '율하', 110),
  ('frame', '바다',       '저 깊은 바다 속에',                'research_records', 80, 'active', '../images/shop/frame_ai_ocean.png',    'frame-ai-ocean',    '일러스트', '율하', 120),
  ('frame', '하얀냥이',   '잉크가 하나도 안 묻었잖니!',      'research_records', 80, 'active', '../images/shop/frame_ai_whitecat.png', 'frame-ai-whitecat', '일러스트', '사월', 130),
  ('frame', '까만냥이',   '잉크가 잔뜩 묻었네!',             'research_records', 80, 'active', '../images/shop/frame_ai_blackcat.png', 'frame-ai-blackcat', '일러스트', '사월', 140),
  ('frame', '고등어냥이', '무늬가 예술적인걸?',              'research_records', 80, 'active', '../images/shop/frame_ai_fishcat.png',  'frame-ai-fishcat',  '일러스트', '사월', 150),
  ('frame', '샴냥이',     '잉크에 얼굴만 콕 찍은 거니?',    'research_records', 80, 'active', '../images/shop/frame_ai_siamcat.png',  'frame-ai-siamcat',  '일러스트', '사월', 160);

-- ── 한정 프레임 ──────────────────────────────
-- ⚠️  이 아이템은 연구기록 80 + 열쇠 1개 이중 통화 가격입니다.
--    현재 shop_items 스키마는 단일 통화만 지원하므로 연구기록 80으로 임시 등록합니다.
--    열쇠 1개 조건 적용 시 shop_items에 secondary_currency / secondary_price 컬럼 추가 필요.
-- ⚠️  판매 종료일(2026-07-31)도 현재 스키마에 expires_at 컬럼 없어 별도 관리 필요.
--    종료 후 아래 쿼리로 status를 hidden으로 변경:
--    UPDATE public.shop_items SET status = 'hidden' WHERE style_key = 'frame-li-bbo';
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
VALUES
  ('frame', '소장이 당신을 먹습니다', '와앙 먹어버릴겁니다!!!', 'research_records', 80, 'active', '../images/shop/frame_li_bbo.png', 'frame-li-bbo', '한정', '율하', 200);
