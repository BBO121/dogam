-- ============================================
-- 프레임 2종 추가(상어가 와앙 / 매어나이트)
-- + 일러스트 스티커 가격 인하
-- 작성일: 2026-07-31
-- ============================================

-- ── 1. 일러스트 스티커 가격 인하 (100 → 60) ───
-- 다른 카테고리의 스티커와 무료 아이템은 변경하지 않습니다.
UPDATE public.shop_items
SET
  price = 60,
  original_price = NULL,
  discount_note = NULL
WHERE item_type = 'sticker'
  AND sub_category = '일러스트'
  AND price = 100;


-- ── 2. 신규 프레임 2종 추가 ───────────────────
-- 카테고리 순서: 일러스트 → 종족 → 한정
-- 매어나이트: 연구기록 100 + 열쇠 1

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
    sort_order
  )
SELECT
  'frame',
  '상어가 와앙',
  '꺄악 상어가 절 잡아먹었.. 어라, 오히려좋아.',
  'research_records',
  100,
  NULL,
  NULL,
  'active',
  '../images/shop/frame_ai_shark.png',
  'frame-ai-shark',
  '일러스트',
  '이상어',
  165
WHERE NOT EXISTS (
  SELECT 1
  FROM public.shop_items
  WHERE style_key = 'frame-ai-shark'
);


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
    sort_order
  )
SELECT
  'frame',
  '매어나이트',
  '당신의 심연을 들여다보면 어쩌구',
  'research_records',
  100,
  'keys',
  1,
  'active',
  '../images/shop/frame_sp_marenight.png',
  'frame-sp-marenight',
  '종족',
  'MS',
  170
WHERE NOT EXISTS (
  SELECT 1
  FROM public.shop_items
  WHERE style_key = 'frame-sp-marenight'
);