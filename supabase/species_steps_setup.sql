-- ============================================
-- 개체 성장 Step 이미지 시스템 (1차)
-- 작성일: 2026-07-27
-- species_steps: Step 정의 테이블 — Step 1(step_order=1)도 이름 지정을 위해 저장 가능.
-- character_step_images: Step 2 이상 이미지만 저장. Step 1 이미지는 기존
-- characters.image_url / original_image_url / thumbnail_url을 그대로 사용.
-- ============================================

CREATE TABLE IF NOT EXISTS public.species_steps (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  species_id  bigint      NOT NULL
                           REFERENCES public.species(id)
                           ON DELETE CASCADE,
  step_order  int         NOT NULL CHECK (step_order >= 1),
  name        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (species_id, step_order)
);

COMMENT ON TABLE public.species_steps IS
'종족별 성장 Step 정의. Step 1(step_order=1)도 이름 지정을 위해 저장 가능하지만, 저장되지 않은 경우 화면에서 기본 Step 1로 처리한다. name이 비어 있으면 화면에서 Step {step_order}로 표시한다.';


CREATE TABLE IF NOT EXISTS public.character_step_images (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  character_id        bigint      NOT NULL
                                   REFERENCES public.characters(id)
                                   ON DELETE CASCADE,
  species_step_id     bigint      NOT NULL
                                   REFERENCES public.species_steps(id)
                                   ON DELETE CASCADE,
  image_url           text,
  original_image_url  text,
  thumbnail_url       text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  UNIQUE (character_id, species_step_id)
);

COMMENT ON TABLE public.character_step_images IS
'개체별 Step 2 이상 성장 이미지. Step 1 이미지는 characters.image_url, original_image_url, thumbnail_url을 사용한다.';


-- ============================================
-- RLS 활성화
-- ============================================

ALTER TABLE public.species_steps
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.character_step_images
ENABLE ROW LEVEL SECURITY;


-- ============================================
-- 기존 정책 제거
-- ============================================

DROP POLICY IF EXISTS "species_steps_select_all"
ON public.species_steps;

DROP POLICY IF EXISTS "species_steps_insert"
ON public.species_steps;

DROP POLICY IF EXISTS "species_steps_update"
ON public.species_steps;

DROP POLICY IF EXISTS "species_steps_delete"
ON public.species_steps;

DROP POLICY IF EXISTS "character_step_images_select_all"
ON public.character_step_images;

DROP POLICY IF EXISTS "character_step_images_insert"
ON public.character_step_images;

DROP POLICY IF EXISTS "character_step_images_update"
ON public.character_step_images;

DROP POLICY IF EXISTS "character_step_images_delete"
ON public.character_step_images;


-- ============================================
-- species_steps 조회
-- ============================================

CREATE POLICY "species_steps_select_all"
ON public.species_steps
FOR SELECT
USING (true);


-- ============================================
-- species_steps 생성
-- 종족주 또는 admin/staff
-- ============================================

CREATE POLICY "species_steps_insert"
ON public.species_steps
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.species s
    WHERE s.id = species_id
      AND s.owner_user_id = auth.uid()
  )
  OR
  (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
);


-- ============================================
-- species_steps 수정
-- ============================================

CREATE POLICY "species_steps_update"
ON public.species_steps
FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.species s
    WHERE s.id = species_id
      AND s.owner_user_id = auth.uid()
  )
  OR
  (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.species s
    WHERE s.id = species_id
      AND s.owner_user_id = auth.uid()
  )
  OR
  (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
);


-- ============================================
-- species_steps 삭제
-- ============================================

CREATE POLICY "species_steps_delete"
ON public.species_steps
FOR DELETE
USING (
  EXISTS (
    SELECT 1
    FROM public.species s
    WHERE s.id = species_id
      AND s.owner_user_id = auth.uid()
  )
  OR
  (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
);


-- ============================================
-- character_step_images 조회
-- ============================================

CREATE POLICY "character_step_images_select_all"
ON public.character_step_images
FOR SELECT
USING (true);


-- ============================================
-- character_step_images 생성
-- 개체 소유주 / 종족주 / admin / staff
-- 캐릭터 종족과 Step 종족이 일치해야 함
-- ============================================

CREATE POLICY "character_step_images_insert"
ON public.character_step_images
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.characters c
    JOIN public.species s
      ON s.name = c.species_name
    JOIN public.species_steps ss
      ON ss.species_id = s.id
    WHERE c.id = character_id
      AND ss.id = species_step_id
      AND (
        c.owner_user_id = auth.uid()
        OR s.owner_user_id = auth.uid()
        OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
      )
  )
);


-- ============================================
-- character_step_images 수정
-- ============================================

CREATE POLICY "character_step_images_update"
ON public.character_step_images
FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.characters c
    JOIN public.species s
      ON s.name = c.species_name
    WHERE c.id = character_id
      AND (
        c.owner_user_id = auth.uid()
        OR s.owner_user_id = auth.uid()
        OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
      )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.characters c
    JOIN public.species s
      ON s.name = c.species_name
    JOIN public.species_steps ss
      ON ss.species_id = s.id
    WHERE c.id = character_id
      AND ss.id = species_step_id
      AND (
        c.owner_user_id = auth.uid()
        OR s.owner_user_id = auth.uid()
        OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
      )
  )
);


-- ============================================
-- character_step_images 삭제
-- ============================================

CREATE POLICY "character_step_images_delete"
ON public.character_step_images
FOR DELETE
USING (
  EXISTS (
    SELECT 1
    FROM public.characters c
    JOIN public.species s
      ON s.name = c.species_name
    WHERE c.id = character_id
      AND (
        c.owner_user_id = auth.uid()
        OR s.owner_user_id = auth.uid()
        OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
      )
  )
);
