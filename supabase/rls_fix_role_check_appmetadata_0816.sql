-- ============================================================
-- [SECURITY 4] role 판정 통일: raw_user_meta_data/user_metadata -> app_metadata
-- 작성일: 2026-08-16
-- 대상: admin_logs, character_gallery (inquiries, site_content는 저장소에 정책 원문이
--       없어 이번 패치에서 제외 - 별도 확인 필요, 보고 본문 참고)
--
-- !!! 실행 전 필수 확인 !!!
-- supabase/app_metadata_staff_migration.sql 1행에 "아직 실행하지 마세요" 명시,
-- 8/14 기준 staff 4명 중 1명(이상어) app_metadata.role 미설정 상태로 기록됨.
-- 이 패치를 먼저 실행하면 이상어 계정이 admin_logs 조회/기록,
-- character_gallery 관리 권한을 즉시 잃습니다.
-- -> app_metadata_staff_migration.sql 실행 여부(또는 이상어 app_metadata.role 세팅 여부)를
--    먼저 확인한 뒤 이 패치를 실행할 것.
-- ============================================================

-- ---------- admin_logs ----------
-- 기존 (supabase/admin_logs_setup.sql:30-48, raw_user_meta_data 사용)
DROP POLICY IF EXISTS "admin_staff_select_logs" ON public.admin_logs;
DROP POLICY IF EXISTS "admin_staff_insert_logs" ON public.admin_logs;

CREATE POLICY "admin_staff_select_logs" ON public.admin_logs
  FOR SELECT USING (
    (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff')
  );

CREATE POLICY "admin_staff_insert_logs" ON public.admin_logs
  FOR INSERT WITH CHECK (
    (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff')
  );

-- ---------- character_gallery ----------
-- 기존 (supabase/character_gallery_setup.sql:77-118, auth.jwt()->'user_metadata' 사용)
-- 소유권 조건(c.owner_user_id/s.owner_user_id = auth.uid())은 그대로 유지, role 부분만 교체.
DROP POLICY IF EXISTS "character_gallery_insert" ON public.character_gallery;
DROP POLICY IF EXISTS "character_gallery_delete" ON public.character_gallery;

CREATE POLICY "character_gallery_insert" ON public.character_gallery
FOR INSERT WITH CHECK (
  uploaded_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.characters c
    LEFT JOIN public.species s ON s.name = c.species_name
    WHERE c.id = character_id
      AND ( c.owner_user_id = auth.uid()
            OR s.owner_user_id = auth.uid()
            OR (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff') )
  )
);

CREATE POLICY "character_gallery_delete" ON public.character_gallery
FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM public.characters c
    LEFT JOIN public.species s ON s.name = c.species_name
    WHERE c.id = character_id
      AND ( c.owner_user_id = auth.uid()
            OR s.owner_user_id = auth.uid()
            OR (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff') )
  )
);

-- character_gallery의 SELECT 정책은 USING(true) 전체 공개이며 role 판정이 없으므로 변경 대상 아님(그대로 유지).
