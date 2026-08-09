-- ============================================
-- 융용 Step 정식 명칭 수정 (융 → 용 표기)
-- 작성일: 2026-08-09
-- 아기융만 '융' 표기가 맞고, 나머지 4단계는 '용' 표기가 정식 명칭임이 확인됨.
-- species_steps.id는 그대로 유지되므로 characters.representative_step_id,
-- character_step_images 등 id 기준 참조에는 영향이 없다.
-- ============================================

UPDATE public.species_steps SET name = '발탁용' WHERE id = 54 AND name = '발탁융';
UPDATE public.species_steps SET name = '수련용' WHERE id = 55 AND name = '수련융';
UPDATE public.species_steps SET name = '승천용' WHERE id = 56 AND name = '승천융';
UPDATE public.species_steps SET name = '재앙용' WHERE id = 57 AND name = '재앙융';

-- 적용 확인
SELECT id, step_order, name FROM public.species_steps WHERE species_id = 172 ORDER BY step_order;
