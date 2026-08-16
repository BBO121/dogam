-- ============================================================
-- [SECURITY 4] role 판정 통일 - 3차 배치 (bug_reports, shop_items, species)
-- 작성일: 2026-08-16
-- rls_fix_role_check_batch2_0816.sql 초안에서 이 3개 테이블만 분리 (내용 변경 없음)
-- nickname 조건은 원문 그대로 유지, role 부분만 app_metadata로 교체
-- species: "Allow insert for species owners"(species_owner 포함)는 이번 배치에서도 제외
-- ============================================================

-- ---------- bug_reports ----------
DROP POLICY IF EXISTS "버그리포트 삭제" ON public.bug_reports;
CREATE POLICY "버그리포트 삭제" ON public.bug_reports
FOR DELETE TO public
USING (
  (COALESCE(NULLIF(((auth.jwt() -> 'user_metadata'::text) ->> 'display_name'::text), ''::text), ((auth.jwt() -> 'user_metadata'::text) ->> 'nickname'::text)) = nickname)
  OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
);

DROP POLICY IF EXISTS "버그리포트 수정" ON public.bug_reports;
CREATE POLICY "버그리포트 수정" ON public.bug_reports
FOR UPDATE TO public
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "버그리포트 조회" ON public.bug_reports;
CREATE POLICY "버그리포트 조회" ON public.bug_reports
FOR SELECT TO public
USING (
  (auth.uid() = user_id)
  OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
  OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'staff'::text)
);

-- ---------- shop_items ----------
DROP POLICY IF EXISTS "shop_items: select" ON public.shop_items;
CREATE POLICY "shop_items: select" ON public.shop_items
FOR SELECT TO public
USING (
  (auth.uid() IS NOT NULL)
  AND ( (status <> 'hidden'::text)
        OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = ANY (ARRAY['admin'::text, 'staff'::text])) )
);

-- ---------- species (admin-only 부분만, species_owner 정책 제외) ----------
DROP POLICY IF EXISTS "종족주/관리자만 수정 가능" ON public.species;
CREATE POLICY "종족주/관리자만 수정 가능" ON public.species
FOR UPDATE TO authenticated
USING ( (owner_user_id = auth.uid()) OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text) )
WITH CHECK ( (owner_user_id = auth.uid()) OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text) );

DROP POLICY IF EXISTS "종족주_또는_관리자_삭제" ON public.species;
CREATE POLICY "종족주_또는_관리자_삭제" ON public.species
FOR DELETE TO public
USING (
  (((auth.jwt() -> 'user_metadata'::text) ->> 'display_name'::text) = owner_nickname)
  OR (((auth.jwt() -> 'user_metadata'::text) ->> 'nickname'::text) = owner_nickname)
  OR (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
);

-- 변경 없음: "Allow insert for species owners" (species_owner 포함, 제외)
