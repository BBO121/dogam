-- 한글 유니코드 정규화(NFC) 백필
--
-- 조사 배경: 앱에서 전체 characters.name / species.name / 유저 nickname·login_id를
-- normalize(x, NFC) 기준으로 대조한 결과, characters.name 4건만 NFD(조합형이 아닌
-- 자모 분리형)로 저장되어 있어 ILIKE 검색 시 완전히 동일해 보이는 이름으로도
-- 검색이 되지 않는 것을 확인함. species.name, 유저 nickname/login_id는
-- 이상 없음(0건) — 해당 대상은 백필 불필요.
--
-- 확인된 4건 (id): 1768 "설표 아씨", 1769 "앙고라토끼 도령",
--                  1770 "모란앵무 도령", 1771 "페넥여우 아씨"
-- 예: "설표"로 검색 시 다른 정상(NFC) 개체는 검색되지만 위 4건은 누락됨을 재현 확인.
--
-- 실행 전 아래 SELECT로 실제 대상을 다시 한 번 확인한 뒤 UPDATE를 실행하세요.

-- 1) 대상 확인 (실행해서 4건이 맞는지, 그 사이 새로 추가된 NFD 데이터는 없는지 확인)
SELECT id, name, length(name) AS len, length(normalize(name, NFC)) AS nfc_len
FROM public.characters
WHERE name <> normalize(name, NFC);

-- 2) 백필 (위 결과를 확인한 뒤 실행)
UPDATE public.characters
SET name = normalize(name, NFC)
WHERE name <> normalize(name, NFC);

-- 참고: species.name / 유저 nickname·login_id는 조사 시점 기준 NFD 데이터가
-- 없었지만, 시간이 지나 새로 들어올 수 있으므로 필요 시 아래 쿼리로 재확인하세요.
-- (유저는 auth.users가 REST로 직접 조회되지 않으므로 SQL Editor에서만 실행 가능)

-- SELECT id, name FROM public.species WHERE name <> normalize(name, NFC);

-- SELECT
--   id,
--   raw_user_meta_data->>'display_name' AS display_name,
--   raw_user_meta_data->>'nickname'     AS nickname,
--   raw_user_meta_data->>'login_id'     AS login_id
-- FROM auth.users
-- WHERE (raw_user_meta_data->>'display_name') <> normalize(raw_user_meta_data->>'display_name', NFC)
--    OR (raw_user_meta_data->>'nickname')     <> normalize(raw_user_meta_data->>'nickname', NFC)
--    OR (raw_user_meta_data->>'login_id')     <> normalize(raw_user_meta_data->>'login_id', NFC);
