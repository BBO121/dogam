-- ============================================================
-- [SECURITY 4] role 판정 통일: inquiries / site_content
-- 작성일: 2026-08-16
-- 원칙: 소유권 조건(nickname/user_id)과 권한 범위는 전혀 변경하지 않음.
--       role 판정 부분(user_metadata -> app_metadata)만 교체.
-- 뽀가 라이브 pg_policies에서 직접 확인한 원문 기준으로 작성.
-- ============================================================

-- ---------- inquiries ----------

-- 1. 문의 삭제 (DELETE)
-- 기존: nickname 소유권 OR user_metadata.role = admin
DROP POLICY IF EXISTS "문의 삭제" ON public.inquiries;

CREATE POLICY "문의 삭제" ON public.inquiries
FOR DELETE
USING (
  (
    COALESCE(
      NULLIF(((auth.jwt() -> 'user_metadata'::text) ->> 'display_name'::text), ''::text),
      ((auth.jwt() -> 'user_metadata'::text) ->> 'nickname'::text)
    ) = nickname
  )
  OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
);

-- 2. 문의 조회 (SELECT)
-- 기존: auth.uid() = user_id OR user_metadata.role IN (admin, staff)
DROP POLICY IF EXISTS "문의 조회" ON public.inquiries;

CREATE POLICY "문의 조회" ON public.inquiries
FOR SELECT
USING (
  auth.uid() = user_id
  OR ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) IN ('admin'::text, 'staff'::text)
);

-- 3. 문의 수정 (UPDATE) - admin 전용, staff 권한 추가하지 않음
-- 기존: user_metadata.role = admin
DROP POLICY IF EXISTS "문의 수정" ON public.inquiries;

CREATE POLICY "문의 수정" ON public.inquiries
FOR UPDATE
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

-- 아래 정책은 변경하지 않음 (role 판정 없음, 그대로 유지):
--   - allow_own_reply_on_inquiries (UPDATE, 본인 user_id)
--   - 문의 삽입 (INSERT)

-- ---------- site_content ----------

-- admin can manage site_content (ALL) - role 판정만 교체
-- 기존: user_metadata.role = admin (USING / WITH CHECK 동일)
DROP POLICY IF EXISTS "admin can manage site_content" ON public.site_content;

CREATE POLICY "admin can manage site_content" ON public.site_content
FOR ALL
TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

-- 아래 정책은 변경하지 않음:
--   - anyone can read site_content (SELECT, public, true)
