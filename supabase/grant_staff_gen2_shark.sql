-- 2기 스태프 이상어(user_id: ed306925-e0e5-44a4-848b-6d27468d598f) 스태프 권한 부여
--
-- 대상
-- 이상어: ed306925-e0e5-44a4-848b-6d27468d598f
--
-- 현재 사이트 전체(프로필 뱃지, admin.html 접근, admin_logs/event_banners RLS,
-- achievement_setup 등)는 전부 auth.users.raw_user_meta_data->>'role' 값만 신뢰한다.
-- (raw_app_meta_data.role은 reset-user-password 함수의 admin 전용 판정에만 쓰이고
--  staff 판정에는 전혀 쓰이지 않으므로, staff 권한 부여 시 건드리지 않는다.)
--
-- 기존 2기 스태프(율하/모로/냐수)와 완전히 동일하게, raw_user_meta_data에
-- role: 'staff'만 병합(merge)한다. 다른 메타데이터(nickname, display_name 등)는
-- 그대로 유지한다.

-- ════════════════════════════════════════════════════════
-- STEP 1 — 변경 전 확인 (기존 2기 스태프와 이상어 비교)
-- 율하/모로/냐수의 user_metadata_role이 모두 'staff'로 나오는지 먼저 확인할 것.
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
  '63bdb2b5-99e9-430d-baaa-33857e384b14'::uuid, -- 율하 (2기, 비교용)
  '3eada7b5-a318-4b1b-b638-36491b023d0a'::uuid, -- 모로 (2기, 비교용)
  'b37d5ad3-af32-4054-8c51-ec0284e0375b'::uuid, -- 냐수 (2기, 비교용)
  'ed306925-e0e5-44a4-848b-6d27468d598f'::uuid  -- 이상어 (권한 부여 대상)
)
ORDER BY created_at ASC;


-- ════════════════════════════════════════════════════════
-- STEP 2 — 이상어 계정에 스태프 권한 부여
-- ════════════════════════════════════════════════════════
DO $$
DECLARE
  target_id uuid := 'ed306925-e0e5-44a4-848b-6d27468d598f'::uuid; -- 이상어
BEGIN
  UPDATE auth.users
  SET
    raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'staff'),
    updated_at = NOW()
  WHERE id = target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '대상 계정을 찾지 못했습니다.';
  END IF;
END $$;


-- ════════════════════════════════════════════════════════
-- STEP 3 — 변경 결과 확인
-- user_metadata_role이 'staff'로 나와야 함
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
WHERE id = 'ed306925-e0e5-44a4-848b-6d27468d598f'::uuid;
