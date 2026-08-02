-- ============================================
-- 스티커 메어나이트1/2 이름·설명 수정
-- - 이름에 "(Marenight)" 영문 표기 추가 (프레임과 통일)
-- - 설명에 "종족주 : MS" 줄 추가 (실제 줄바꿈 문자, 프레임과 동일 방식)
-- 작성일: 2026-08-02
-- ============================================

UPDATE public.shop_items
SET
  name        = '메어나이트1(Marenight)',
  description = '심연과...
종족주 : MS'
WHERE style_key = 'sticker-sp-marenight1';

UPDATE public.shop_items
SET
  name        = '메어나이트2(Marenight)',
  description = '좌절과...
종족주 : MS'
WHERE style_key = 'sticker-sp-marenight2';
