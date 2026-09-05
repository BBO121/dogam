-- ============================================================
-- [MIGRATION] LABBER 개체 POD / CARTRIDGE / SUBJECT — 자유입력 문자열 → trait code 배열
-- 작성일: 2026-09-06
-- (구 labber_cartridge_traits_migration_0905.sql 를 POD/SUBJECT 까지 확장·대체)
--
-- 배경:
--   LABBER(species_id=204) 개체 수정창의 POD/CARTRIDGE/SUBJECT 입력이 자유 텍스트에서
--   "관리소 특성 선택형"으로 바뀌었다. 저장 포맷도 문자열 → trait code 배열(jsonb).
--   프론트(js/labber-traits.js)는 문자열/배열 양쪽을 모두 읽으므로 이 SQL을 돌리지 않아도
--   화면은 정상 동작한다. 실행하면 저장 포맷이 통일된다.
--
--   CARTRIDGE: 복수 — 문자열에 등장하는 모든 특성명 → 배열
--   POD/SUBJECT: 단일 — 문자열에서 가장 먼저 등장하는 특성명 1개 → 길이 1 배열
--   매핑되는 특성명이 하나도 없으면 원본 문자열을 그대로 둔다.
--
-- 되돌리기: custom_field_values 는 jsonb 라 원본 문자열 백업 없이 되돌릴 수 없다.
--   실행 전 반드시 STEP 1 결과를 저장해 둘 것.
-- ============================================================

-- ── STEP 1. (실행 전) 현재 값 확인 — 결과를 어딘가에 복사해 두세요 ──
SELECT c.id, c.name,
       c.custom_field_values->'POD'       AS pod_now,
       c.custom_field_values->'CARTRIDGE' AS cartridge_now,
       c.custom_field_values->'SUBJECT'   AS subject_now
FROM characters c
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND (c.custom_field_values ?| array['POD','CARTRIDGE','SUBJECT']);


-- ============================================================
-- STEP 2. 변환 — 필드별로 UPDATE 3개 (map CTE 는 문 단위라 각 UPDATE 에 인라인).
--   position(nm IN 값) > 0  = "값 문자열에 그 특성명이 포함됨".
-- ============================================================

-- 2-A. CARTRIDGE (복수)
WITH map(nm, code, ord) AS (VALUES
  ('액체 돌출','labber_cartridge_liquid_protrusion',1),
  ('액체 부착','labber_cartridge_liquid_attach',2),
  ('포드 분할','labber_cartridge_pod_split',3),
  ('포드 선형 연장','labber_cartridge_pod_linear_extension',4)
)
UPDATE characters c
SET custom_field_values = jsonb_set(
  c.custom_field_values, '{CARTRIDGE}',
  (SELECT jsonb_agg(m.code ORDER BY m.ord) FROM map m
   WHERE position(m.nm IN (c.custom_field_values->>'CARTRIDGE')) > 0)
)
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND jsonb_typeof(c.custom_field_values->'CARTRIDGE') = 'string'
  AND EXISTS (SELECT 1 FROM map m
              WHERE position(m.nm IN (c.custom_field_values->>'CARTRIDGE')) > 0);

-- 2-B. POD (단일 — 가장 먼저 등장하는 특성명)
WITH map(nm, code, ord) AS (VALUES
  ('원형 포드','labber_pod_round',1),
  ('원통형 포드','labber_pod_cylinder',2),
  ('삼각형 포드','labber_pod_triangle',3),
  ('사각형 포드','labber_pod_square',4),
  ('반원형 포드','labber_pod_semicircle',5)
)
UPDATE characters c
SET custom_field_values = jsonb_set(
  c.custom_field_values, '{POD}',
  jsonb_build_array((
    SELECT m.code FROM map m
    WHERE position(m.nm IN (c.custom_field_values->>'POD')) > 0
    ORDER BY position(m.nm IN (c.custom_field_values->>'POD')), m.ord
    LIMIT 1
  ))
)
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND jsonb_typeof(c.custom_field_values->'POD') = 'string'
  AND EXISTS (SELECT 1 FROM map m
              WHERE position(m.nm IN (c.custom_field_values->>'POD')) > 0);

-- 2-C. SUBJECT (단일 — 가장 먼저 등장하는 특성명)
WITH map(nm, code, ord) AS (VALUES
  ('흰동가리','labber_subject_clownfish',1),
  ('개복치','labber_subject_sunfish',2),
  ('베타','labber_subject_betta',3),
  ('참새','labber_subject_sparrow',4),
  ('까마귀','labber_subject_crow',5),
  ('오리','labber_subject_duck',6),
  ('볼파이톤','labber_subject_ballpython',7),
  ('크레스티드 게코','labber_subject_crestedgecko',8),
  ('쿠터 거북이','labber_subject_cooterturtle',9),
  ('크리쳐','labber_subject_creature',10),
  ('종족','labber_subject_species',11)
)
UPDATE characters c
SET custom_field_values = jsonb_set(
  c.custom_field_values, '{SUBJECT}',
  jsonb_build_array((
    SELECT m.code FROM map m
    WHERE position(m.nm IN (c.custom_field_values->>'SUBJECT')) > 0
    ORDER BY position(m.nm IN (c.custom_field_values->>'SUBJECT')), m.ord
    LIMIT 1
  ))
)
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND jsonb_typeof(c.custom_field_values->'SUBJECT') = 'string'
  AND EXISTS (SELECT 1 FROM map m
              WHERE position(m.nm IN (c.custom_field_values->>'SUBJECT')) > 0);


-- ── STEP 3. (실행 후) 확인 ──
SELECT c.id, c.name,
       c.custom_field_values->'POD'       AS pod_after,
       c.custom_field_values->'CARTRIDGE' AS cartridge_after,
       c.custom_field_values->'SUBJECT'   AS subject_after
FROM characters c
WHERE c.species_name = (SELECT name FROM species WHERE id = 204)
  AND (c.custom_field_values ?| array['POD','CARTRIDGE','SUBJECT']);
