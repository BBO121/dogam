-- delete_user RPC 함수
-- 유저 삭제 전 FK 참조 테이블을 순서대로 정리하고 auth.users 삭제
--
-- CASCADE 설정된 테이블 (자동 처리, 별도 구문 불필요):
--   user_achievements, user_species_views, user_character_views,
--   attendance_logs, attendance_rewards,
--   user_wallets, currency_logs (counterpart_user_id → SET NULL),
--   user_achievement_counters, user_items, user_equipment
--
-- CASCADE 없는 테이블 (아래에서 명시적으로 삭제):
--   adoption_applications, adoptions, inquiries,
--   bug_reports, character_folders, species_applications

CREATE OR REPLACE FUNCTION public.delete_user(target_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
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

GRANT EXECUTE ON FUNCTION public.delete_user(UUID) TO authenticated;
