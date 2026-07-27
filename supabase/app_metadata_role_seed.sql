-- reset-user-password 긴급 패치를 위한 최소 시드 스크립트 (v2 — 안전 버전)
--
-- ⚠️ v1에서 지적된 문제: raw_user_meta_data.role이 있는 "모든" 유저를
-- 자동으로 app_metadata에 복사하는 방식은 위험하다. raw_user_meta_data는
-- 유저 본인이 supabase.auth.updateUser()로 직접 조작 가능한 값이라,
-- 이 시드를 돌리기 "전"에 누군가 이미 자기 user_metadata.role을
-- 'admin'으로 위조해뒀다면, 그 위조값까지 그대로 신뢰 영역인
-- app_metadata로 영구 복사되어 실제 admin 권한을 갖게 된다.
--
-- 그래서 이 버전은 자동 일괄 복사를 하지 않는다. 운영자가 실제로 admin인지
-- "직접 확인"한 UUID만 아래 STEP 2에 명시적으로 나열해서, 그 사람들에게만
-- app_metadata.role = 'admin'을 설정한다.
--
-- staff/species_owner는 reset-user-password가 admin만 허용하므로 이번
-- 시드 대상에 포함하지 않는다(전체 마이그레이션 때 별도로 다룬다).
--
-- 전체 role 마이그레이션 때는 이 "무조건 user_metadata를 믿고 일괄
-- 백필"하는 방식 자체를 쓰지 않고, 실제 종족 소유 관계(species.owner_user_id)·
-- 관리자 명단 등 신뢰 가능한 별도 데이터와 대조하는 검증 단계를 거쳐야 한다.
-- (이번 긴급 패치 범위에서는 admin 한 건만 수동 확인하면 되므로 별도
--  검증 로직 없이 운영자 육안 확인으로 충분하다.)

-- ════════════════════════════════════════════════════════
-- STEP 1 — 후보 목록 확인 (반드시 직접 눈으로 검토할 것 — 자동 신뢰 금지)
-- claimed_role='admin'이라고 해서 실제 admin이라는 뜻이 아니다.
-- 이 목록에서 본인이 실제로 아는 관리자 계정만 골라낸다.
-- 낯선 계정이 섞여 있다면 이미 위조를 시도한 흔적일 수 있으니
-- 그 계정은 STEP 2에 절대 포함하지 말고 별도로 조사할 것.
-- ════════════════════════════════════════════════════════
SELECT
  id,
  email,
  raw_user_meta_data->>'nickname'     AS nickname,
  raw_user_meta_data->>'display_name' AS display_name,
  raw_user_meta_data->>'role'         AS claimed_user_metadata_role,
  raw_app_meta_data->>'role'          AS current_app_metadata_role,
  created_at
FROM auth.users
WHERE raw_user_meta_data->>'role' = 'admin'
ORDER BY created_at ASC;

-- ════════════════════════════════════════════════════════
-- STEP 2 — 위 목록을 직접 검토한 뒤, 실제 admin으로 "확인된" UUID만
-- 아래 배열에 채워서 실행한다. 예시 UUID는 반드시 실제 값으로 교체할 것.
-- ════════════════════════════════════════════════════════
DO $$
DECLARE
  verified_admin_ids uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000000000'::uuid  -- TODO: 실제로 확인한 admin UUID로 교체
    -- , '11111111-1111-1111-1111-111111111111'::uuid  -- 여러 명이면 이렇게 추가
  ];
BEGIN
  UPDATE auth.users
  SET raw_app_meta_data =
    COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'admin')
  WHERE id = ANY(verified_admin_ids);
END $$;

-- ════════════════════════════════════════════════════════
-- STEP 3 — 결과 확인 (STEP 2에서 지정한 사람에게만 반영됐는지 확인)
-- ════════════════════════════════════════════════════════
SELECT
  id,
  email,
  raw_user_meta_data->>'role' AS user_metadata_role,
  raw_app_meta_data->>'role'  AS app_metadata_role
FROM auth.users
WHERE raw_app_meta_data->>'role' = 'admin';
