-- ============================================
-- 일러스트 스티커 추가
-- 작성일: 2026-06-23
-- ============================================

-- ── 1. credit 컬럼 추가 (미실행 시) ──
-- ALTER TABLE public.shop_items ADD COLUMN credit text;

-- ── 2. 기존 공오 스티커 수정 ──
UPDATE public.shop_items
SET
  name         = '공오',
  description  = '내 뿔이랑 날개 뺏어가지마!',
  sub_category = '기본',
  credit       = '뽀'
WHERE style_key = 'sticker-free-05';

-- ── 3. 일러스트 스티커 7종 추가 ──
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
VALUES
(
  'sticker', '비눗방울', '둥실둥실 떠다니는 비눗방울',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_bubble.png',   'sticker-ai-bubble',
  '일러스트', '아요', 20
),
(
  'sticker', '천사', '머리 위에 링이 달렸어요!',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_angel.png',    'sticker-ai-angel',
  '일러스트', '아요', 30
),
(
  'sticker', '악마', '케헤헤, 괴롭힐래!',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_devil.png',    'sticker-ai-devil',
  '일러스트', '아요', 40
),
(
  'sticker', '분양중', '저를 분양합니다!',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_adoption.png', 'sticker-ai-adoption',
  '일러스트', '아요', 50
),
(
  'sticker', '병아리', '뚱땅뚱땅 병아리',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_chick.png',    'sticker-ai-chick',
  '일러스트', '아요', 60
),
(
  'sticker', '독', '발밑을 조심하세요!',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_poison.png',   'sticker-ai-poison',
  '일러스트', '아요', 70
),
(
  'sticker', '이빨', '누구의 입속일까?',
  'research_records', 60, 'active',
  '../images/shop/sticker_ai_fang.png',     'sticker-ai-fang',
  '일러스트', '아요', 80
);
