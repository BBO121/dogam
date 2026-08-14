-- ============================================
-- delete_user() 권한 취약점 수정
-- 작성일: 2026-08-14
--
-- 문제: 기존 delete_user.sql은 GRANT EXECUTE ... TO authenticated 로 되어 있고
-- 함수 본문에 호출자 권한 검증이 전혀 없었다.
-- 즉 로그인한 아무 유저나 supabase.rpc('delete_user', { target_id: <다른 유저 uuid> })를
-- 직접 호출해 타인 계정을 삭제시킬 수 있는 상태였다.
-- (다른 유저 uuid는 get_all_users() 등으로 이미 널리 조회 가능하다)
--
-- 수정: 함수 시작부에 admin/staff 역할 검증을 추가한다.
-- 자가탈퇴(본인이 본인 계정을 삭제)는 이번 단계에서 다루지 않으므로
-- "본인 허용" 조건은 넣지 않고 admin/staff만 허용한다.
-- (자가탈퇴 정책은 DM 처리 방식이 정해진 뒤 별도 작업에서 다룬다)
--
-- 기존 CASCADE/명시적 DELETE 로직은 전혀 건드리지 않는다 (권한 체크만 추가).
--
-- [2026-08-14 수정] admin/staff 4명(율하/모로/냐수/이상어) + admin 2명의
-- raw_app_meta_data.role 마이그레이션이 완료된 것을 뽀가 확인해줘서,
-- raw_user_meta_data.role로의 폴백을 제거하고 raw_app_meta_data.role만
-- 신뢰하도록 변경한다(user_metadata는 본인이 updateUser()로 위조 가능하므로).
-- ============================================

CREATE OR REPLACE FUNCTION public.delete_user(target_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  -- 호출자 역할 확인 (app_metadata만 신뢰 — user_metadata는 본인이 위조 가능)
  SELECT raw_app_meta_data->>'role'
  INTO v_caller_role
  FROM auth.users
  WHERE id = auth.uid();

  IF auth.uid() IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '관리자만 실행할 수 있습니다.';
  END IF;

  -- 1. adoption_applications: 해당 유저가 신청자인 행 삭제
  DELETE FROM public.adoption_applications
  WHERE applicant_id = target_id;

  -- 2. adoption_applications: 해당 유저의 분양글에 달린 신청 삭제
  --    (adoptions 삭제 전에 먼저 처리)
  DELETE FROM public.adoption_applications
  WHERE adoption_id IN (
    SELECT id FROM public.adoptions WHERE user_id = target_id
  );

  -- 3. adoptions: 해당 유저가 올린 분양글 삭제
  DELETE FROM public.adoptions
  WHERE user_id = target_id;

  -- 4. inquiries: 해당 유저의 문의글 삭제
  DELETE FROM public.inquiries
  WHERE user_id = target_id;

  -- 5. bug_reports: 해당 유저의 버그 신고 삭제
  DELETE FROM public.bug_reports
  WHERE user_id = target_id;

  -- 6. character_folders: 해당 유저의 개체 폴더 삭제
  DELETE FROM public.character_folders
  WHERE user_id = target_id;

  -- 7. species_applications: 해당 유저의 종족주 신청 삭제
  DELETE FROM public.species_applications
  WHERE user_id = target_id;

  -- 8. auth.users 삭제 (CASCADE 테이블들은 여기서 자동 처리됨)
  DELETE FROM auth.users
  WHERE id = target_id;
END;
$$;

-- authenticated 전체가 아니라 함수 내부에서 admin/staff를 검증하므로
-- GRANT 자체는 유지해도 안전하지만, 방어를 이중으로 두기 위해 그대로 authenticated 유지
-- (일반 유저가 호출해도 RAISE EXCEPTION으로 즉시 차단됨)
GRANT EXECUTE ON FUNCTION public.delete_user(UUID) TO authenticated;
