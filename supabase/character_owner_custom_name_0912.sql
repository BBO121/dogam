-- ============================================================
-- 개체 이름 이원화: characters.owner_custom_name 신규 컬럼
-- 작성일: 2026-09-12
--
-- 정책
--   - characters.name            = 종족주 설정 "등록명" (기존 값 그대로 승계, 변경/백필 없음)
--   - characters.owner_custom_name = 소유주 설정 "소유주명" (신규, nullable, 전체 NULL로 시작)
--
-- 이 파일 구성
--   1) ALTER TABLE로 컬럼 추가 (기존 행은 전부 NULL — 백필 없음)
--   2) characters_public 뷰 재생성 (character_artist_setup.sql의 최신 컬럼 목록 + owner_custom_name)
--      → get_character_for_edit()는 RETURNS SETOF characters + 본문이 SELECT * 라서
--        이 파일에서 재정의할 필요가 없다 (character_special_badge_setup.sql 주석 참고).
--   3) BEFORE UPDATE 트리거 1개로 아래 두 가지를 DB 레벨에서 강제
--      a. 소유권(owner_user_id) 변경 시 owner_custom_name을 같은 UPDATE 문 안에서 자동 NULL 초기화
--         → accept_transfer / confirm_adoption_transfer / (소스 미보유) complete_adoption_transfer /
--           admin.html 강제 이전 / bulk_link_*_owner 계열 등 characters.owner_user_id를 바꾸는
--           모든 현재·미래 경로에 공통 적용됨. 각 RPC를 개별 수정할 필요가 없다.
--      b. 일반 소유주는 name을, 소유주 아닌 사람은 owner_custom_name을 못 바꾸게 컬럼 단위로 검증
--         (admin/staff 전체 우회 유지, 기존 characters_update_by_role_or_owner 행 단위 RLS는
--          그대로 두고 트리거로 추가 방어선만 얹는다 — 정책 재설계 아님)
-- ============================================================

-- ────────────────────────────────────────────
-- 1. 컬럼 추가
-- ────────────────────────────────────────────
ALTER TABLE public.characters
  ADD COLUMN IF NOT EXISTS owner_custom_name text;

COMMENT ON COLUMN public.characters.owner_custom_name IS
'소유주가 개인적으로 설정하는 이름. NULL이면 미설정. 종족주 설정 등록명(characters.name)과 별개이며 종족주 등록명을 덮어쓰지 않는다. 소유권 이전 시 트리거(characters_name_edit_guard)가 자동으로 NULL 초기화한다.';


-- ────────────────────────────────────────────
-- 2. characters_public 뷰 재생성
--    (character_artist_setup.sql의 최신 컬럼 목록 그대로 + owner_custom_name 한 컬럼만 추가)
-- ────────────────────────────────────────────
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
  c.representative_step_id,
  c.special_badge,
  c.artist_user_ids,
  c.artist_external,
  c.artist_nickname,
  c.owner_custom_name
FROM public.characters c;

GRANT SELECT ON public.characters_public TO anon, authenticated;

COMMENT ON VIEW public.characters_public IS
'characters의 공개 안전 버전. owner_contact/designer_contact 제외, designer_external은 각 원소에서 contact 키를 제거해 이름만 남긴다. special_badge, artist_user_ids/artist_external/artist_nickname, owner_custom_name(소유주 설정 이름)도 읽기 전용으로 포함. 연락처가 필요한 본인/관리자 편집 화면은 get_character_for_edit() RPC를 사용한다.';


-- ────────────────────────────────────────────
-- 3. 이름 컬럼 단위 권한 가드 + 소유권 이전 시 자동 초기화 트리거
-- ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.characters_name_edit_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role             text := ((auth.jwt() -> 'app_metadata') ->> 'role');
  v_is_privileged    boolean := v_role = ANY (ARRAY['admin', 'staff']);
  v_is_owner         boolean := (auth.uid() IS NOT NULL AND OLD.owner_user_id = auth.uid());
  v_is_species_owner boolean := EXISTS (
    SELECT 1 FROM public.species s
    WHERE s.name = OLD.species_name AND s.owner_user_id = auth.uid()
  );
  v_owner_changed    boolean := NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id;
BEGIN
  -- (a) 소유권이 바뀌는 UPDATE는 owner_custom_name을 같은 문장 안에서 무조건 초기화한다.
  --     호출자가 이 컬럼에 어떤 값을 실어 보냈든 여기서 덮어써 안전하게 정리한다.
  IF v_owner_changed THEN
    NEW.owner_custom_name := NULL;
  END IF;

  -- admin/staff는 기존과 동일하게 전 컬럼 자유롭게 수정 가능(운영 정책 유지)
  IF v_is_privileged THEN
    RETURN NEW;
  END IF;

  -- (b-1) 등록명(characters.name)은 종족주만 변경 가능
  IF NEW.name IS DISTINCT FROM OLD.name AND NOT v_is_species_owner THEN
    RAISE EXCEPTION '등록명은 종족주만 수정할 수 있어요.';
  END IF;

  -- (b-2) 소유주 설정 이름(owner_custom_name)은 현재 소유주만 변경 가능.
  --       단, 소유권 이전으로 인한 자동 초기화((a)에서 처리)는 이 검사에서 제외한다 —
  --       그렇지 않으면 이전을 받는 새 소유주가 이전 트랜잭션 자체를 막아버리게 된다.
  IF NOT v_owner_changed
     AND NEW.owner_custom_name IS DISTINCT FROM OLD.owner_custom_name
     AND NOT v_is_owner THEN
    RAISE EXCEPTION '소유주 설정 이름은 현재 소유주만 수정할 수 있어요.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_characters_name_edit_guard ON public.characters;
CREATE TRIGGER trg_characters_name_edit_guard
BEFORE UPDATE ON public.characters
FOR EACH ROW
EXECUTE FUNCTION public.characters_name_edit_guard();

COMMENT ON FUNCTION public.characters_name_edit_guard IS
'characters UPDATE 트리거: (1) owner_user_id가 바뀌는 모든 UPDATE에서 owner_custom_name을 자동 NULL 초기화(원자적, RPC별 개별 수정 불필요) (2) admin/staff를 제외하고 name은 종족주만, owner_custom_name은 현재 소유주만 바꿀 수 있도록 컬럼 단위로 강제. 기존 characters_update_by_role_or_owner 행 단위 RLS는 그대로 두고 추가 방어선으로 얹은 것— 정책 재설계 아님.';


-- ────────────────────────────────────────────
-- 4. 적용 확인용 쿼리 (실행 후 눈으로 확인만, 데이터 변경 없음)
-- ────────────────────────────────────────────
-- SELECT id, name, owner_custom_name FROM public.characters LIMIT 5;
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'characters_public' ORDER BY ordinal_position;
-- SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.characters'::regclass AND NOT tgisinternal;
