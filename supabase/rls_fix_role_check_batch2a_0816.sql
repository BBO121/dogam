-- ============================================================
-- [SECURITY 4] role 판정 통일 - 1차 배치 (dev_logs, event_banners, events, update_notes)
-- 작성일: 2026-08-16
-- rls_fix_role_check_batch2_0816.sql 초안에서 이 4개 테이블만 분리 (내용 변경 없음)
-- ============================================================

-- ---------- dev_logs ----------
DROP POLICY IF EXISTS "dev_logs_admin_delete" ON public.dev_logs;
CREATE POLICY "dev_logs_admin_delete" ON public.dev_logs
FOR DELETE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "dev_logs_admin_insert" ON public.dev_logs;
CREATE POLICY "dev_logs_admin_insert" ON public.dev_logs
FOR INSERT TO authenticated
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "dev_logs_admin_update" ON public.dev_logs;
CREATE POLICY "dev_logs_admin_update" ON public.dev_logs
FOR UPDATE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

-- ---------- event_banners ----------
DROP POLICY IF EXISTS "event_banners_admin_delete" ON public.event_banners;
CREATE POLICY "event_banners_admin_delete" ON public.event_banners
FOR DELETE TO public
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "event_banners_admin_insert" ON public.event_banners;
CREATE POLICY "event_banners_admin_insert" ON public.event_banners
FOR INSERT TO public
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "event_banners_admin_update" ON public.event_banners;
CREATE POLICY "event_banners_admin_update" ON public.event_banners
FOR UPDATE TO public
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

-- ---------- events ----------
DROP POLICY IF EXISTS "events_admin_delete" ON public.events;
CREATE POLICY "events_admin_delete" ON public.events
FOR DELETE TO public
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "events_admin_insert" ON public.events;
CREATE POLICY "events_admin_insert" ON public.events
FOR INSERT TO public
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "events_admin_update" ON public.events;
CREATE POLICY "events_admin_update" ON public.events
FOR UPDATE TO public
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

-- ---------- update_notes ----------
DROP POLICY IF EXISTS "update_notes admin delete" ON public.update_notes;
CREATE POLICY "update_notes admin delete" ON public.update_notes
FOR DELETE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "update_notes admin insert" ON public.update_notes;
CREATE POLICY "update_notes admin insert" ON public.update_notes
FOR INSERT TO authenticated
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "update_notes admin update" ON public.update_notes;
CREATE POLICY "update_notes admin update" ON public.update_notes
FOR UPDATE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);
