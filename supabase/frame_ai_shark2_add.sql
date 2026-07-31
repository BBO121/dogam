-- ============================================
-- 일러스트 프레임 추가: 상어와 함께
-- 작성일: 2026-07-31
-- ============================================

INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, credit, sort_order)
SELECT
  'frame', '상어와 함께', '상어가 어디있지? ...여깄잖아!?',
  'research_records', 100, 'active',
  '../images/shop/frame_ai_shark2.png', 'frame-ai-shark2', '일러스트', '이상어', 167
WHERE NOT EXISTS (
  SELECT 1 FROM public.shop_items WHERE style_key = 'frame-ai-shark2'
);
