-- ============================================================
-- [SECURITY 4] role 판정 통일 - 4차(마지막) 배치 (character_step_images, characters)
-- 작성일: 2026-08-16
-- rls_fix_role_check_batch2_0816.sql 초안에서 이 2개 테이블만 분리 (내용 변경 없음)
-- owner_user_id 소유권 조건은 그대로 유지, role 부분만 app_metadata로 교체
-- characters: "owner can delete own", "species_owner can delete in own species"는
-- nickname 전용(role 판정 없음)이라 이번 배치에서도 제외
-- ============================================================

-- ---------- character_step_images ----------
DROP POLICY IF EXISTS "character_step_images_delete" ON public.character_step_images;
CREATE POLICY "character_step_images_delete" ON public.character_step_images
FOR DELETE TO public
USING (
  EXISTS (
    SELECT 1 FROM characters c
    JOIN species s ON (s.name = c.species_name)
    WHERE c.id = character_step_images.character_id
      AND ( c.owner_user_id = auth.uid()
            OR s.owner_user_id = auth.uid()
            OR ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = ANY (ARRAY['admin'::text, 'staff'::text]) )
  )
);

DROP POLICY IF EXISTS "character_step_images_insert" ON public.character_step_images;
CREATE POLICY "character_step_images_insert" ON public.character_step_images
FOR INSERT TO public
WITH CHECK (
  EXISTS (
    SELECT 1 FROM characters c
    JOIN species s ON (s.name = c.species_name)
    JOIN species_steps ss ON (ss.species_id = s.id)
    WHERE c.id = character_step_images.character_id
      AND ss.id = character_step_images.species_step_id
      AND ( c.owner_user_id = auth.uid()
            OR s.owner_user_id = auth.uid()
            OR ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = ANY (ARRAY['admin'::text, 'staff'::text]) )
  )
);

DROP POLICY IF EXISTS "character_step_images_update" ON public.character_step_images;
CREATE POLICY "character_step_images_update" ON public.character_step_images
FOR UPDATE TO public
USING (
  EXISTS (
    SELECT 1 FROM characters c
    JOIN species s ON (s.name = c.species_name)
    WHERE c.id = character_step_images.character_id
      AND ( c.owner_user_id = auth.uid()
            OR s.owner_user_id = auth.uid()
            OR ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = ANY (ARRAY['admin'::text, 'staff'::text]) )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM characters c
    JOIN species s ON (s.name = c.species_name)
    JOIN species_steps ss ON (ss.species_id = s.id)
    WHERE c.id = character_step_images.character_id
      AND ss.id = character_step_images.species_step_id
      AND ( c.owner_user_id = auth.uid()
            OR s.owner_user_id = auth.uid()
            OR ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = ANY (ARRAY['admin'::text, 'staff'::text]) )
  )
);

-- ---------- characters ----------
DROP POLICY IF EXISTS "characters: admin can delete any" ON public.characters;
CREATE POLICY "characters: admin can delete any" ON public.characters
FOR DELETE TO authenticated
USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);

DROP POLICY IF EXISTS "characters: admin or own species owner can insert" ON public.characters;
CREATE POLICY "characters: admin or own species owner can insert" ON public.characters
FOR INSERT TO authenticated
WITH CHECK (
  (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
  OR EXISTS (
    SELECT 1 FROM species
    WHERE species.name = characters.species_name AND species.owner_user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "characters_update_by_role_or_owner" ON public.characters;
CREATE POLICY "characters_update_by_role_or_owner" ON public.characters
FOR UPDATE TO public
USING (
  (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = ANY (ARRAY['admin'::text, 'staff'::text]))
  OR (owner_user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM species WHERE species.name = characters.species_name AND species.owner_user_id = auth.uid())
)
WITH CHECK (
  (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = ANY (ARRAY['admin'::text, 'staff'::text]))
  OR (owner_user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM species WHERE species.name = characters.species_name AND species.owner_user_id = auth.uid())
);
