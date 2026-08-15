-- ============================================
-- 옥토몬스터 / 쁘띠아라크네 이름 표기 변경
-- "이름 영문명" → "이름(영문명)" (메어나이트(Marenight)와 동일 표기 규칙)
-- shop_species_5set_add_0815.sql을 이미 실행한 경우를 위한 안전장치
-- (아직 실행 전이라면 이 UPDATE는 대상이 없어 아무 영향도 없음)
-- 작성일: 2026-08-15
-- ============================================

UPDATE public.shop_items
SET name = '옥토몬스터(Octomonster)'
WHERE style_key IN ('frame-sp-octomonster', 'sticker-sp-octomonster');

UPDATE public.shop_items
SET name = '쁘띠아라크네(Petit Arachne)'
WHERE style_key IN ('frame-sp-petitarachne', 'sticker-sp-petitarachne');
