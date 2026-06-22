-- ============================================
-- 심플 프레임 6종 추가
-- 작성일: 2026-06-22
-- ============================================

-- ── 1. sub_category 컬럼 추가 (없을 경우) ──
ALTER TABLE public.shop_items
ADD COLUMN IF NOT EXISTS sub_category text;

-- ── 2. 기존 공오 프레임에 sub_category 지정 ──
UPDATE public.shop_items
SET sub_category = '기본'
WHERE style_key IN ('frame-mint', 'frame-orange')
  AND sub_category IS NULL;

-- ── 3. 심플 프레임 6종 INSERT ──
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, style_key, sub_category, sort_order)
VALUES
  ('frame', '심플 스카이',    '맑은 하늘빛 단색 프레임',     'research_records', 10, 'active', 'frame-simple-sky',      '심플', 10),
  ('frame', '심플 라벤더',    '차분한 라벤더 단색 프레임',   'research_records', 10, 'active', 'frame-simple-lavender', '심플', 20),
  ('frame', '심플 로즈',      '사랑스러운 로즈 단색 프레임', 'research_records', 10, 'active', 'frame-simple-rose',     '심플', 30),
  ('frame', '심플 레몬',      '상큼한 레몬 단색 프레임',     'research_records', 10, 'active', 'frame-simple-lemon',    '심플', 40),
  ('frame', '심플 라임',      '싱그러운 라임 단색 프레임',   'research_records', 10, 'active', 'frame-simple-lime',     '심플', 50),
  ('frame', '심플 그레이',    '세련된 그레이 단색 프레임',   'research_records', 10, 'active', 'frame-simple-gray',     '심플', 60);
