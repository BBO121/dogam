-- ============================================================
-- [MIGRATION] LABBER 개체 INK — 자유입력 문자열 → trait code 배열
-- 작성일: 2026-09-07
-- (labber_trait_fields_migration_0906.sql 의 INK 버전. POD/CARTRIDGE/SUBJECT 는 0906 에서 처리됨)
--
-- 배경:
--   LABBER(species_id=204) 개체 수정창의 INK 입력이 자유 텍스트에서 "관리소 특성 선택형(복수)"
--   으로 바뀌었다. 저장 포맷도 문자열 → trait code 배열(jsonb).
--   프론트(js/labber-traits.js)는 문자열/배열 양쪽을 모두 읽으므로 이 SQL 을 돌리지 않아도
--   개체 상세 화면은 정상 동작한다(매칭 안 되는 자유입력은 원문 그대로 노출).
--   ★ 단, 변환하지 않은 개체를 수정창에서 저장하면 매칭 안 된 INK 원문은 사라진다.
--     (수정창 picker 가 자유입력을 code 로 인식하지 못해 빈 선택으로 저장하기 때문)
--
--   INK: 복수 — 값 문자열에 등장하는 모든 색상명 → 배열
--   매핑되는 색상이 하나도 없으면 원본 문자열을 그대로 둔다(절대 비우지 않음).
--
-- INK trait code (js/labber-traits.js TRAIT_DATA.ink 와 1:1):
--   labber_ink_red / _orange / _yellow / _green / _cyan / _blue / _purple / _pink  = 표준
--   labber_ink_neutral                                                            = 특이
--
-- 되돌리기: custom_field_values 는 jsonb 라 원본 문자열 백업 없이 되돌릴 수 없다.
--   실행 전 반드시 STEP 1 결과를 저장해 둘 것.
-- 재실행 안전(idempotent): 이미 배열로 바뀐 행은 STEP 2 의 jsonb_typeof='string' 가드에 걸려 건너뛴다.
-- ============================================================


-- ── STEP 1. (실행 전) 현재 INK 값 확인 — 결과를 어딘가에 복사해 두세요 ──
--   여기서 나온 자유입력 표현을 보고 STEP 2 의 색상 동의어(map)를 필요 시 보강하세요.
SELECT c.id, c.name,
       jsonb_typeof(c.custom_field_values->'INK') AS ink_type,
       c.custom_field_values->'INK'               AS ink_now
FROM characters c
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND (c.custom_field_values ? 'INK')
ORDER BY c.name;


-- ============================================================
-- STEP 2. 변환 — INK (복수).
--   position(lower(nm) IN lower(값)) > 0 = "값 문자열에 그 색상 표현이 포함됨".
--   한 색상당 동의어를 여러 줄로 두고, code 기준으로 묶어서(min ord) 배열을 만든다.
-- ============================================================
WITH map(nm, code, ord) AS (VALUES
  ('Ink-RED','labber_ink_red',1),        ('RED','labber_ink_red',1),        ('레드','labber_ink_red',1),      ('빨','labber_ink_red',1),        ('적색','labber_ink_red',1),
  ('Ink-ORANGE','labber_ink_orange',2),  ('ORANGE','labber_ink_orange',2),  ('오렌지','labber_ink_orange',2), ('주황','labber_ink_orange',2),
  ('Ink-YELLOW','labber_ink_yellow',3),  ('YELLOW','labber_ink_yellow',3),  ('옐로','labber_ink_yellow',3),   ('노랑','labber_ink_yellow',3),   ('노란','labber_ink_yellow',3),   ('황색','labber_ink_yellow',3),
  ('Ink-GREEN','labber_ink_green',4),    ('GREEN','labber_ink_green',4),    ('그린','labber_ink_green',4),    ('초록','labber_ink_green',4),    ('녹색','labber_ink_green',4),
  ('Ink-CYAN','labber_ink_cyan',5),      ('CYAN','labber_ink_cyan',5),      ('시안','labber_ink_cyan',5),     ('청록','labber_ink_cyan',5),     ('민트','labber_ink_cyan',5),
  ('Ink-BLUE','labber_ink_blue',6),      ('BLUE','labber_ink_blue',6),      ('블루','labber_ink_blue',6),     ('파랑','labber_ink_blue',6),     ('파란','labber_ink_blue',6),     ('청색','labber_ink_blue',6),
  ('Ink-PURPLE','labber_ink_purple',7),  ('PURPLE','labber_ink_purple',7),  ('퍼플','labber_ink_purple',7),   ('보라','labber_ink_purple',7),   ('자주','labber_ink_purple',7),
  ('Ink-PINK','labber_ink_pink',8),      ('PINK','labber_ink_pink',8),      ('핑크','labber_ink_pink',8),     ('분홍','labber_ink_pink',8),
  ('Ink-NEUTRAL','labber_ink_neutral',9),('NEUTRAL','labber_ink_neutral',9),('뉴트럴','labber_ink_neutral',9),('중성','labber_ink_neutral',9),  ('무채','labber_ink_neutral',9)
)
UPDATE characters c
SET custom_field_values = jsonb_set(
  c.custom_field_values, '{INK}',
  (SELECT jsonb_agg(t.code ORDER BY t.ord)
   FROM (SELECT m.code, min(m.ord) AS ord
         FROM map m
         WHERE position(lower(m.nm) IN lower(c.custom_field_values->>'INK')) > 0
         GROUP BY m.code) t)
)
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND jsonb_typeof(c.custom_field_values->'INK') = 'string'
  AND EXISTS (SELECT 1 FROM map m
              WHERE position(lower(m.nm) IN lower(c.custom_field_values->>'INK')) > 0);


-- ── STEP 3. (실행 후) 확인 ──
SELECT c.id, c.name,
       jsonb_typeof(c.custom_field_values->'INK') AS ink_type,
       c.custom_field_values->'INK'               AS ink_after
FROM characters c
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND (c.custom_field_values ? 'INK')
ORDER BY c.name;
