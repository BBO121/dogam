-- ============================================
-- 아요님 일러스트 스티커 7종 무료 지급
-- 대상: e0fee7ef-2316-43f9-b498-ed06d9809791
-- 사유: 디자인 제작자 보상
-- 작성일: 2026-06-23
-- ============================================

INSERT INTO public.user_items (user_id, item_id, quantity)
SELECT
  'e0fee7ef-2316-43f9-b498-ed06d9809791'::uuid,
  s.id,
  1
FROM public.shop_items s
WHERE s.style_key IN (
  'sticker-ai-bubble',
  'sticker-ai-angel',
  'sticker-ai-devil',
  'sticker-ai-adoption',
  'sticker-ai-chick',
  'sticker-ai-poison',
  'sticker-ai-fang'
)
ON CONFLICT (user_id, item_id) DO NOTHING;
