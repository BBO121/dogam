-- slots 테이블 (디자인권)
-- 소유권은 반드시 owner_user_id(UUID) 기준으로만 처리합니다.
-- owner_name은 사이트 밖 유저(Site-OFF) 표시용 전용입니다.

CREATE TABLE IF NOT EXISTS public.slots (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  species_id         uuid        NOT NULL REFERENCES public.species(id) ON DELETE CASCADE,
  name               text        NOT NULL,
  designer           text,
  owner_user_id      uuid,
  owner_name         text,
  slot_number        text,
  description        text,
  image_url          text,
  original_image_url text,
  thumbnail_url      text,
  trait_values       jsonb,
  status             text        NOT NULL DEFAULT 'active',
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- RLS 활성화
ALTER TABLE public.slots ENABLE ROW LEVEL SECURITY;

-- 전체 읽기 허용
CREATE POLICY "slots_select_all"
  ON public.slots FOR SELECT
  USING (true);

-- 로그인 유저만 삽입 가능
CREATE POLICY "slots_insert_auth"
  ON public.slots FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- 해당 종족의 종족주(owner_user_id)만 수정 가능
CREATE POLICY "slots_update_species_owner"
  ON public.slots FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.species
      WHERE species.id = slots.species_id
        AND species.owner_user_id = auth.uid()
    )
  );

-- 해당 종족의 종족주(owner_user_id)만 삭제 가능
CREATE POLICY "slots_delete_species_owner"
  ON public.slots FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.species
      WHERE species.id = slots.species_id
        AND species.owner_user_id = auth.uid()
    )
  );
