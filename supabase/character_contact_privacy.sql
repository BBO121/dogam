-- ============================================
-- 캐릭터 연락처(owner_contact / designer_contact / designer_external.contact) 비공개 전환
-- 작성일: 2026-08-14
--
-- 문제:
--   characters 테이블은 RLS가 아예 없어(레포 전체에 characters용 CREATE POLICY가
--   없음) anon/authenticated 모두 전체 컬럼을 기본적으로 조회할 수 있다.
--   character_gallery는 RLS가 있지만 SELECT 정책이 USING (true)라 사실상 전체 공개다.
--   그런데 두 테이블 모두 실제 연락처가 담기는 컬럼이 있다:
--     characters.owner_contact      (text)  — 오프사이트 소유자 연락처
--     characters.designer_contact   (text)  — 레거시 단일 디자이너 연락처
--     characters.designer_external  (jsonb) — [{name, contact}, ...] 외부 디자이너 목록
--     character_gallery.designer_external (jsonb) — 갤러리 항목별 외부 디자이너 목록
--   designer_external는 사이트 회원이 아닌 사람의 이름+연락처까지 담을 수 있다.
--
-- 방침(뽀 확인):
--   - 연락처(contact)는 완전 비공개 — 본인(글쓴이/소유주) 또는 admin/staff만.
--   - 이름/닉네임 등 크레딧 표시는 계속 공개.
--
-- 방식: RLS는 행 단위라 컬럼을 못 가리므로 사용하지 않는다. 대신
--   1) 문제의 3개 컬럼을 anon/authenticated에게서 컬럼 단위로 REVOKE.
--   2) 공개 화면은 연락처를 뺀 뷰(characters_public/character_gallery_public)로 조회.
--      (뷰는 소유자 없이 CREATE하는 쪽 — 즉 이 SQL을 실행하는 role — 권한으로
--      내부적으로 원본 테이블을 읽으므로, 컬럼 REVOKE와 무관하게 정상 동작한다.
--      PostgreSQL의 표준 동작이며 별도 SECURITY DEFINER 설정이 필요 없다.)
--   3) 본인/관리자가 자기 캐릭터를 수정/이전할 때는 연락처를 포함한 전체 데이터가
--      필요하므로, 권한 검증 후 원본 그대로 반환하는 get_character_for_edit RPC를 둔다.
--
-- ⚠️ 순서 중요: 이 SQL을 실행하기 전에 프론트엔드가 이미 아래로 전환되어 있어야 한다
--    (같은 커밋에서 함께 수정됨):
--      - character.html: CHAR_SELECT/GALLERY_SELECT 대상을 *_public 뷰로 변경
--      - character-edit.html / character-transfer.html / transfer-confirm.html:
--        characters.select('*') → get_character_for_edit(id) RPC 호출로 교체
--      - admin.html / profile.html: designer_external을 읽는 characters 조회를
--        characters_public으로 교체
--    프론트를 먼저 바꾸지 않고 REVOKE부터 실행하면, 위 화면들이 즉시
--    "permission denied for column owner_contact" 에러로 깨진다.
-- ============================================


-- ============================================
-- 1. 컬럼 단위 REVOKE
-- ============================================
REVOKE SELECT (owner_contact, designer_contact, designer_external)
  ON public.characters
  FROM anon, authenticated;

REVOKE SELECT (designer_external)
  ON public.character_gallery
  FROM anon, authenticated;


-- ============================================
-- 2. characters_public 뷰 — 연락처 3개 제외, designer_external은 contact 키만 제거
-- ============================================
CREATE OR REPLACE VIEW public.characters_public AS
SELECT
  c.id,
  c.name,
  c.species_name,
  c.image_url,
  c.thumbnail_url,
  c.default_image_index,
  c.additional_images,
  c.owner_nickname,
  c.owner_user_id,
  c.owner_is_offsite,
  c.owner_description,
  c.designer_nickname,
  c.designer_user_ids,
  (
    SELECT COALESCE(jsonb_agg(elem - 'contact'), '[]'::jsonb)
    FROM jsonb_array_elements(COALESCE(c.designer_external, '[]'::jsonb)) AS elem
  ) AS designer_external,
  c.char_number,
  c.description,
  c.is_sensitive,
  c.sensitive_note,
  c.char_sections,
  c.custom_field_values,
  c.char_categories,
  c.allow_free_adoption,
  c.allow_resale,
  c.allow_paid_adoption,
  c.allow_other_adoption,
  c.pending_transfer,
  c.created_at,
  c.representative_step_id
FROM public.characters c;

GRANT SELECT ON public.characters_public TO anon, authenticated;

COMMENT ON VIEW public.characters_public IS
'characters의 공개 안전 버전. owner_contact/designer_contact 제외, designer_external은 각 원소에서 contact 키를 제거해 이름만 남긴다. 연락처가 필요한 본인/관리자 편집 화면은 get_character_for_edit() RPC를 사용한다.';


-- ============================================
-- 3. character_gallery_public 뷰 — 동일 방식
-- ============================================
CREATE OR REPLACE VIEW public.character_gallery_public AS
SELECT
  g.id,
  g.character_id,
  g.uploaded_by,
  g.designer_user_ids,
  (
    SELECT COALESCE(jsonb_agg(elem - 'contact'), '[]'::jsonb)
    FROM jsonb_array_elements(COALESCE(g.designer_external, '[]'::jsonb)) AS elem
  ) AS designer_external,
  g.designer_nickname,
  g.category,
  g.description,
  g.image_url,
  g.thumbnail_url,
  g.created_at
FROM public.character_gallery g;

GRANT SELECT ON public.character_gallery_public TO anon, authenticated;

COMMENT ON VIEW public.character_gallery_public IS
'character_gallery의 공개 안전 버전. designer_external의 contact 키를 제거해 이름만 남긴다.';


-- ============================================
-- 4. get_character_for_edit(character_id) — 본인/관리자 전용, 연락처 포함 원본 반환
-- ============================================
CREATE OR REPLACE FUNCTION public.get_character_for_edit(p_character_id bigint)
RETURNS SETOF public.characters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_owner_id    uuid;
  v_caller_role text;
BEGIN
  SELECT owner_user_id INTO v_owner_id
  FROM public.characters WHERE id = p_character_id;

  IF v_owner_id IS NULL AND NOT FOUND THEN
    RETURN;
  END IF;

  -- [2026-08-14] admin/staff app_metadata 마이그레이션 완료 확인 후
  -- user_metadata 폴백 제거 — app_metadata만 신뢰
  SELECT raw_app_meta_data->>'role'
  INTO v_caller_role
  FROM auth.users WHERE id = auth.uid();

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다';
  END IF;

  IF v_owner_id IS DISTINCT FROM auth.uid()
     AND v_caller_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '본인 또는 관리자만 조회할 수 있습니다.';
  END IF;

  RETURN QUERY
  SELECT * FROM public.characters WHERE id = p_character_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_character_for_edit(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_character_for_edit(bigint) TO authenticated;

COMMENT ON FUNCTION public.get_character_for_edit IS
'캐릭터 편집/이전 화면 전용. 호출자가 owner_user_id 본인이거나 admin/staff일 때만 owner_contact/designer_contact/designer_external(원본, contact 포함)까지 전체 컬럼을 반환한다. SECURITY DEFINER로 컬럼 REVOKE를 우회하되, 함수 내부에서 자체적으로 권한을 검증한다.';
