-- ============================================
-- 프레임 카테고리 순서 강제 정렬: 일러스트 → 종족 → 한정
-- 작성일: 2026-07-31
-- ============================================

UPDATE public.shop_items
SET sort_order = 170
WHERE item_type = 'frame' AND sub_category = '종족';

UPDATE public.shop_items
SET sort_order = 200
WHERE item_type = 'frame' AND sub_category = '한정';
