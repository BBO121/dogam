-- ============================================
-- staff 권한을 raw_app_meta_data로 안전하게 이전 (1회성 마이그레이션)
-- 작성일: 2026-08-14
--
-- ⚠️ 아직 실행하지 마세요 — 뽀 검토용 초안입니다.
--
-- 배경:
--   grant_staff_gen2_shark.sql(8/3)에 "raw_app_meta_data.role은 admin 전용
--   판정에만 쓰이고 staff 판정에는 전혀 쓰이지 않는다"고 명시돼 있어서,
--   delete_user()/get_character_for_edit()/resolve_users_by_identifiers()의
--   권한 체크를 raw_app_meta_data.role 단독으로 바꾸면 현재 staff 전원이
--   즉시 권한을 잃을 뻔했습니다(뽀가 지적).
--
--   실제 라이브 집계 결과(2026-08-14, 뽀 확인):
--     user_metadata_role | app_metadata_role | 인원수
--     (없음)             | (없음)             | 133
--     species_owner      | (없음)             | 66
--     staff              | staff              | 3   ← 이미 동기화됨
--     admin               | admin              | 2   ← 이미 동기화됨(마이그레이션 불필요)
--     staff              | (없음)             | 1   ← 이 1명만 누락
--
--   admin은 2/2 전원 이미 app_metadata가 채워져 있어 이번 마이그레이션
--   대상에서 제외합니다(할 게 없음). staff만 다룹니다.
--
-- 신뢰 가능한 소스(코드 근거, 뽀가 직접 작성/실행한 것으로 보이는 운영 스크립트
-- 3개가 서로 일치하는 명단을 담고 있었음 — 상세 근거는 대화 내 보고서 참고):
--   supabase/grant_staff_gen2_shark.sql (8/3) — 이상어 staff 부여, 율하/모로/냐수 비교 대상 명시
--   supabase/remove_staff_gen1_role.sql (8/1) — 아요/사월 실권한 이미 회수(대상 아님)
--   supabase/grant_staff_badge.sql      (8/10, 가장 최근) — 뽀/율하/모로/냐수/이상어=staff 뱃지 7명 명시
--
-- 이 마이그레이션은 위 스크립트들에 반복해서 등장하는 4명(율하/모로/냐수/이상어)의
-- UUID만 명시적으로 나열해서 처리합니다. user_metadata.role='staff'인 "모든" 계정을
-- 자동으로 훑어서 복사하는 방식은 쓰지 않습니다(일반 유저가 스스로 조작해뒀을 수
-- 있는 값을 무조건 신뢰하지 않기 위함 — app_metadata_role_seed.sql의 기존 안전
-- 패턴을 그대로 따름).
--
-- WHERE 조건에 "현재 app_metadata와 다를 때만" UPDATE하도록 넣어서, 이미 동기화된
-- 3명(추정: 율하/모로/냐수 중 일부)은 건드리지 않고 누락된 1명만 실제로 반영됩니다
-- (멱등 — 여러 번 실행해도 안전).
-- ============================================


-- ════════════════════════════════════════════════════════
-- STEP 1 — 실행 전 확인 (반드시 직접 눈으로 검토할 것)
-- 아래 4명 각각의 user_metadata_role/app_metadata_role이 예상과 같은지 확인.
-- "누락"으로 표시된 것과 실제로 app_metadata_role이 NULL인 게 일치하는지 봐주세요.
-- ════════════════════════════════════════════════════════
SELECT
  id,
  raw_user_meta_data->>'nickname'     AS nickname,
  raw_user_meta_data->>'display_name' AS display_name,
  raw_user_meta_data->>'role'         AS user_metadata_role,
  raw_app_meta_data->>'role'          AS app_metadata_role,
  CASE
    WHEN (raw_app_meta_data->>'role') IS DISTINCT FROM 'staff' THEN '→ 이번에 반영됨'
    ELSE '(이미 일치 — 변경 없음)'
  END AS 예상_결과
FROM auth.users
WHERE deleted_at IS NULL
  AND id IN (
    '63bdb2b5-99e9-430d-baaa-33857e384b14'::uuid, -- 율하
    '3eada7b5-a318-4b1b-b638-36491b023d0a'::uuid, -- 모로
    'b37d5ad3-af32-4054-8c51-ec0284e0375b'::uuid, -- 냐수
    'ed306925-e0e5-44a4-848b-6d27468d598f'::uuid  -- 이상어
  )
ORDER BY created_at ASC;


-- ════════════════════════════════════════════════════════
-- STEP 2 — 위 STEP 1 결과를 직접 확인한 뒤 실행
-- app_metadata에 이미 role='staff'가 있는 사람은 WHERE 조건 때문에 건드리지 않고,
-- 없는 사람만 실제로 UPDATE됩니다.
-- ════════════════════════════════════════════════════════
DO $$
DECLARE
  verified_staff_ids uuid[] := ARRAY[
    '63bdb2b5-99e9-430d-baaa-33857e384b14'::uuid, -- 율하
    '3eada7b5-a318-4b1b-b638-36491b023d0a'::uuid, -- 모로
    'b37d5ad3-af32-4054-8c51-ec0284e0375b'::uuid, -- 냐수
    'ed306925-e0e5-44a4-848b-6d27468d598f'::uuid  -- 이상어
  ];
  updated_count integer;
BEGIN
  UPDATE auth.users
  SET raw_app_meta_data =
    COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'staff')
  WHERE id = ANY(verified_staff_ids)
    AND (raw_app_meta_data->>'role') IS DISTINCT FROM 'staff';

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RAISE NOTICE '실제로 변경된 계정 수: %', updated_count;
END $$;


-- ════════════════════════════════════════════════════════
-- STEP 3 — 결과 확인
-- 4명 전원 app_metadata_role = 'staff'로 나와야 함
-- ════════════════════════════════════════════════════════
SELECT
  id,
  raw_user_meta_data->>'nickname' AS nickname,
  raw_user_meta_data->>'role'     AS user_metadata_role,
  raw_app_meta_data->>'role'      AS app_metadata_role
FROM auth.users
WHERE id IN (
  '63bdb2b5-99e9-430d-baaa-33857e384b14'::uuid,
  '3eada7b5-a318-4b1b-b638-36491b023d0a'::uuid,
  'b37d5ad3-af32-4054-8c51-ec0284e0375b'::uuid,
  'ed306925-e0e5-44a4-848b-6d27468d598f'::uuid
);
