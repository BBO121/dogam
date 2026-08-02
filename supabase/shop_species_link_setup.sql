-- ============================================
-- 상점 아이템 → 종족 페이지 링크 기능
-- - shop_items.species_link_id 컬럼 추가 (species.html?id= 값)
-- - 메어나이트 프레임/스티커 2종에 종족 id 113 지정
-- - 설명에서 "종족주 : MS" 줄 삭제 (버튼으로 대체)
-- 작성일: 2026-08-02
-- ============================================

ALTER TABLE public.shop_items
  ADD COLUMN IF NOT EXISTS species_link_id text;

UPDATE public.shop_items
SET species_link_id = '113'
WHERE style_key IN ('frame-sp-marenight', 'sticker-sp-marenight1', 'sticker-sp-marenight2');

UPDATE public.shop_items
SET description = '당신의 심연을 들여다보면 어쩌구'
WHERE style_key = 'frame-sp-marenight';

UPDATE public.shop_items
SET description = '심연과...'
WHERE style_key = 'sticker-sp-marenight1';

UPDATE public.shop_items
SET description = '좌절과...'
WHERE style_key = 'sticker-sp-marenight2';
