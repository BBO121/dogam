-- ============================================
-- 캐릭터 고유 갤러리 (character_gallery)
-- 작성일: 2026-08-13
-- 갤러리는 소유주 개인이 아니라 character_id에 귀속된다.
-- 개체 소유권이 이전되어도 character_id는 바뀌지 않으므로 갤러리는 그대로 유지되고,
-- RLS의 관리 권한(INSERT/DELETE)은 "현재" characters.owner_user_id / species.owner_user_id를
-- 매 요청마다 조회해서 판단하므로 이전 후에는 새 소유주가 자동으로 관리 권한을 가진다.
-- uploaded_by는 등록 당시 업로더를 남기는 기록용 컬럼일 뿐, 삭제 권한 판단에는 쓰지 않는다.
--
-- 권한 범위는 기존 character_step_images(성장 Step 이미지, species_steps_setup.sql)와 동일한
-- 패턴을 따른다: 캐릭터 소유주 OR 종족주 OR admin/staff.
-- ============================================

CREATE TABLE IF NOT EXISTS public.character_gallery (
  id                  bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  character_id        bigint      NOT NULL
                                   REFERENCES public.characters(id)
                                   ON DELETE CASCADE,
  uploaded_by         uuid        NOT NULL
                                   REFERENCES auth.users(id),

  -- 디자이너: character-register.html과 동일하게 사이트 유저는 uuid로, 사이트 외부 유저는
  -- jsonb 배열({name, contact})로 저장한다. designer_nickname은 등록 시점 표시용 캐시.
  designer_user_ids   uuid[]      NOT NULL DEFAULT '{}',
  designer_external   jsonb       NOT NULL DEFAULT '[]'::jsonb,
  designer_nickname   text,

  category            text,
  description         text,      -- 선택 입력. 그림에 대한 설명.

  image_url           text        NOT NULL,
  thumbnail_url       text,       -- GIF는 애니메이션 보존을 위해 썸네일을 만들지 않고 null (그리드에서 image_url 사용)

  created_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.character_gallery IS
'캐릭터(character_id)에 귀속되는 갤러리. 소유권 이전과 무관하게 유지되며, uploaded_by는 등록 당시 업로더 기록일 뿐 관리 권한 기준이 아니다 (관리 권한은 현재 캐릭터 소유주/종족주/admin,staff 기준).';

CREATE INDEX IF NOT EXISTS character_gallery_character_id_idx
  ON public.character_gallery (character_id);


-- ============================================
-- RLS 활성화
-- ============================================

ALTER TABLE public.character_gallery
ENABLE ROW LEVEL SECURITY;


-- ============================================
-- 기존 정책 제거 (재실행 대비)
-- ============================================

DROP POLICY IF EXISTS "character_gallery_select_all" ON public.character_gallery;
DROP POLICY IF EXISTS "character_gallery_insert"     ON public.character_gallery;
DROP POLICY IF EXISTS "character_gallery_delete"     ON public.character_gallery;


-- ============================================
-- 조회 — 캐릭터 조회 정책과 동일하게 전체 공개
-- (characters/species_steps/character_step_images 모두 SELECT는 USING (true))
-- ============================================

CREATE POLICY "character_gallery_select_all"
ON public.character_gallery
FOR SELECT
USING (true);


-- ============================================
-- 등록 — 캐릭터 소유주 / 종족주 / admin / staff
-- uploaded_by는 반드시 요청자 본인이어야 함 (타인 명의로 기록 방지)
-- ============================================

CREATE POLICY "character_gallery_insert"
ON public.character_gallery
FOR INSERT
WITH CHECK (
  uploaded_by = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.characters c
    LEFT JOIN public.species s ON s.name = c.species_name
    WHERE c.id = character_id
      AND (
        c.owner_user_id = auth.uid()
        OR s.owner_user_id = auth.uid()
        OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
      )
  )
);


-- ============================================
-- 삭제 — 캐릭터 소유주 / 종족주 / admin / staff
-- uploaded_by = auth.uid() 조건은 의도적으로 사용하지 않음
-- (갤러리는 업로더 개인 소유가 아니라 캐릭터 귀속 데이터이므로, 캐릭터 이전 후에는
--  새 소유주가 이전 업로더의 갤러리도 삭제 관리할 수 있어야 한다)
-- ============================================

CREATE POLICY "character_gallery_delete"
ON public.character_gallery
FOR DELETE
USING (
  EXISTS (
    SELECT 1
    FROM public.characters c
    LEFT JOIN public.species s ON s.name = c.species_name
    WHERE c.id = character_id
      AND (
        c.owner_user_id = auth.uid()
        OR s.owner_user_id = auth.uid()
        OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'staff')
      )
  )
);


-- ============================================
-- Storage 경로 (참고용 — 별도 정책 불필요)
-- ============================================
-- 기존 캐릭터/종족 이미지와 동일하게 공용 'images' 버킷을 사용하며,
-- 이 버킷에는 폴더 단위 RLS가 걸려 있지 않으므로(레포 내 별도 정책 파일 없음,
-- 기존 이미지 업로드 전부 동일 버킷에 flat/폴더 혼용으로 저장) 새 정책을 추가하지 않는다.
-- 경로 규칙: character-gallery/{character_id}/{timestamp}_{random}.{ext}
--          character-gallery/{character_id}/{timestamp}_{random}_thumb.jpg
