-- ============================================================
-- [SECURITY 4] role 판정 통일 - 2차 배치 (guides, notices)
-- 작성일: 2026-08-16
-- rls_fix_role_check_batch2_0816.sql 초안에서 이 2개 테이블만 분리 (내용 변경 없음)
-- 중복 정책 존재 - 정리/삭제하지 않고 각각 role 부분만 교체
-- ============================================================

-- ---------- guides (중복 정책 2쌍) ----------
DROP POLICY IF EXISTS "admin_can_delete_guides" ON public.guides;
CREATE POLICY "admin_can_delete_guides" ON public.guides
FOR DELETE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "admin_can_insert_guides" ON public.guides;
CREATE POLICY "admin_can_insert_guides" ON public.guides
FOR INSERT TO authenticated
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "guides_delete_admin" ON public.guides;
CREATE POLICY "guides_delete_admin" ON public.guides
FOR DELETE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "guides_insert_admin" ON public.guides;
CREATE POLICY "guides_insert_admin" ON public.guides
FOR INSERT TO authenticated
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "guides_update_admin" ON public.guides;
CREATE POLICY "guides_update_admin" ON public.guides
FOR UPDATE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

-- ---------- notices (중복 정책 2쌍) ----------
DROP POLICY IF EXISTS "admin_can_delete_notices" ON public.notices;
CREATE POLICY "admin_can_delete_notices" ON public.notices
FOR DELETE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "admin_can_insert_notices" ON public.notices;
CREATE POLICY "admin_can_insert_notices" ON public.notices
FOR INSERT TO authenticated
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "관리자만 공지 삭제" ON public.notices;
CREATE POLICY "관리자만 공지 삭제" ON public.notices
FOR DELETE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "관리자만 공지 수정" ON public.notices;
CREATE POLICY "관리자만 공지 수정" ON public.notices
FOR UPDATE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "관리자만 공지 작성" ON public.notices;
CREATE POLICY "관리자만 공지 작성" ON public.notices
FOR INSERT TO authenticated
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);
