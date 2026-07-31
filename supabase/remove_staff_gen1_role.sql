-- 1기 스태프(아요, 사월) 계정의 실제 관리자/스태프 권한 회수
--
-- 대상
-- 아요: e0fee7ef-2316-43f9-b498-ed06d9809791
-- 사월: 5b31c7c2-575d-46a9-803b-937898e4e081
--
-- 프론트엔드의 '스태프(1기)' 배지는 STAFF_GEN1 배열로 표시되므로
-- auth.users의 role을 제거해도 명예 배지는 그대로 유지된다.
--
-- 현재 권한 판정에서 app_metadata.role을 사용하는 곳이 있으므로
-- raw_app_meta_data와 raw_user_meta_data 양쪽의 role을 모두 제거한다.

-- ════════════════════════════════════════════════════════
-- STEP 1 — 변경 전 계정 및 권한 확인
-- ════════════════════════════════════════════════════════
SELECT
  id,
  email,
  raw_user_meta_data->>'nickname'     AS nickname,
  raw_user_meta_data->>'display_name' AS display_name,
  raw_user_meta_data->>'role'         AS user_metadata_role,
  raw_app_meta_data->>'role'          AS app_metadata_role,
  created_at
FROM auth.users
WHERE id IN (
  'e0fee7ef-2316-43f9-b498-ed06d9809791'::uuid,
  '5b31c7c2-575d-46a9-803b-937898e4e081'::uuid
)
ORDER BY created_at ASC;


-- ════════════════════════════════════════════════════════
-- STEP 2 — 관리자/스태프 권한 제거
-- ════════════════════════════════════════════════════════
DO $$
DECLARE
  target_ids uuid[] := ARRAY[
    'e0fee7ef-2316-43f9-b498-ed06d9809791'::uuid, -- 아요
    '5b31c7c2-575d-46a9-803b-937898e4e081'::uuid  -- 사월
  ];
BEGIN
  UPDATE auth.users
  SET
    raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) - 'role',
    raw_app_meta_data  = COALESCE(raw_app_meta_data, '{}'::jsonb) - 'role',
    updated_at = NOW()
  WHERE id = ANY(target_ids);

  IF NOT FOUND THEN
    RAISE EXCEPTION '대상 계정을 찾지 못했습니다.';
  END IF;
END $$;


-- ════════════════════════════════════════════════════════
-- STEP 3 — 변경 결과 확인
-- user_metadata_role과 app_metadata_role이 모두 NULL이어야 함
-- ════════════════════════════════════════════════════════
SELECT
  id,
  email,
  raw_user_meta_data->>'nickname'     AS nickname,
  raw_user_meta_data->>'display_name' AS display_name,
  raw_user_meta_data->>'role'         AS user_metadata_role,
  raw_app_meta_data->>'role'          AS app_metadata_role,
  updated_at
FROM auth.users
WHERE id IN (
  'e0fee7ef-2316-43f9-b498-ed06d9809791'::uuid,
  '5b31c7c2-575d-46a9-803b-937898e4e081'::uuid
);