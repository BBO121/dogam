-- ============================================================
-- [CRITICAL 2] species_applications RLS 최소권한 패치 (초안, 미실행)
-- 작성일: 2026-08-16
-- 목적: FOR ALL TO public USING(true) WITH CHECK(true) 제거.
--       anon 접근 차단, authenticated는 본인 신청만 CRUD, admin/staff는 전체 관리.
--
-- 조사 결과 요약:
--   - 저장소에 CREATE POLICY 원문이 없어(대시보드 직접 생성) 정책명을 알 수 없음.
--     -> 아래는 테이블의 모든 기존 정책을 이름과 무관하게 동적으로 제거하는 방식 사용.
--   - 신청자 본인: 목록 조회(SELECT, user_id=본인), 중복확인(SELECT), 신청 등록(INSERT).
--     자기 신청 UPDATE/DELETE 하는 프론트 코드는 없음.
--   - 관리자(admin/staff): 전체 조회, 답변/상태 UPDATE(species-apply-detail.html:236-321),
--     삭제(species-apply-detail.html:340 deleteApply, deleteBtn은 isAdminUser일 때만 노출 -
--     species-apply-detail.html:117,211-224 확인 완료. 일반 사용자는 삭제 버튼 자체가 없음).
--   - anon 접근 필요한 코드 없음 (전부 로그인 가드 있음).
--   - 프론트의 관리자 판정(isAdminOrStaff)은 user_metadata.role을 쓰지만 이는 UI 표시용
--     게이트일 뿐이고, 실제 서버 권한은 아래 RLS(app_metadata 기준)가 담당하므로 안전함.
--
-- 영향 프론트: pages/species-apply.html, species-apply-write.html,
--             species-apply-detail.html, js/sidebar.js(count 조회)
-- ============================================================

-- 기존 정책 전체 동적 제거 (정책명을 몰라도 안전하게 제거)
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'species_applications'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.species_applications', pol.policyname);
  END LOOP;
END $$;

-- 본인 신청 + admin/staff 전체 조회
CREATE POLICY "species_applications_select_own_or_staff"
ON public.species_applications
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff')
);

-- 본인 신청만 등록
CREATE POLICY "species_applications_insert_own"
ON public.species_applications
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- admin/staff만 답변/상태 수정
CREATE POLICY "species_applications_update_staff"
ON public.species_applications
FOR UPDATE
TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff'))
WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff'));

-- admin/staff만 삭제 (일반 사용자 삭제 버튼 자체가 프론트에 없음 - 확인됨)
CREATE POLICY "species_applications_delete_staff"
ON public.species_applications
FOR DELETE
TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff'));

-- anon 정책 없음 = anon 접근 완전 차단 (의도된 동작)
