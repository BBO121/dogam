-- ============================================================
-- 개체 상세 페이지 "특별 분류 뱃지" (운영자 전용) 신규 기능
-- 작성일: 2026-08-23 / 수정: 2026-08-23 (뽀 리뷰 반영 — INSERT 경로 방어,
-- admin 단독 허용으로 축소, characters_public 뷰 원본 정의 재확인)
--
-- 목적: 특정 개체(예: 종족연구소 콜라보 개체)에 운영자가 직접 지정하는
-- 특별 뱃지를 기존 분류 뱃지("공허" 등) 바로 왼쪽에 표시한다.
-- 일반 유저 등록/수정 UI에는 입력 항목을 추가하지 않고, 운영자가 SQL로
-- 직접 값을 지정/해제한다.
--
-- [조사 결과 — INSERT 경로]
--   characters에는 실제로 일반(비-admin) 유저가 쓸 수 있는 INSERT 경로가
--   있다: RLS 정책 "characters: admin or own species owner can insert"
--   (rls_fix_role_check_batch2d_0816.sql)가 admin뿐 아니라 자기 종족의
--   종족주(species.owner_user_id = auth.uid())에게도 INSERT를 허용한다.
--   실제 프론트 경로는 pages/character-register.html:1469의
--   sb.from('characters').insert({...}) — 종족주가 자기 종족에 개체를
--   등록하는 정상 기능이다. 이 INSERT는 키를 전부 명시적으로 나열하고
--   special_badge를 포함하지 않아 UI로는 절대 값이 실리지 않지만, RLS의
--   WITH CHECK는 "이 종족의 소유주인가"만 검사하고 컬럼 값까지는 보지
--   않으므로, 종족주 계정이 브라우저 콘솔 등으로 직접
--   sb.from('characters').insert({..., special_badge:'specieslab_collab'})
--   를 호출하면 RLS만으로는 막히지 않는다. → INSERT 시점 가드가 반드시
--   필요하다(UPDATE 가드만으로는 불충분).
--
-- [조사 결과 — UPDATE 경로]
--   UPDATE는 "characters_update_by_role_or_owner"(동일 파일)가 admin/staff
--   외에 owner_user_id 본인, 종족주에게도 행 단위로 UPDATE를 허용한다.
--   RLS는 행 단위라 "이 컬럼만 admin 전용"으로 컬럼 단위 제한을 걸 수
--   없고, character-edit.html 등 기존 모든 UPDATE 호출은 키를 명시적으로
--   나열해서 special_badge를 절대 포함하지 않지만(예: character-edit.html
--   :1203, 1701), 브라우저 콘솔로 supabase-js를 직접 호출하는 우회까지
--   막으려면 DB 레벨 강제가 필요하다.
--
-- [권한 범위]
--   이 뱃지는 일반적인 스태프 운영 기능이 아니라 운영자가 특정 특별
--   개체에 직접 부여하는 메타데이터라, staff는 제외하고 app_metadata.role
--   = 'admin'인 브라우저 요청만 허용한다. Supabase SQL Editor처럼 요청에
--   JWT가 없는(auth.uid() IS NULL) 직접 DB 운영 작업은 기존 의도대로
--   항상 허용한다.
--
-- [트리거 구조]
--   INSERT용/UPDATE용 트리거를 분리했다(가독성/안전성 우선, 뽀 요청).
--   같은 가드 함수를 공유하고 TG_OP로 분기한다.
--     - INSERT: WHEN (NEW.special_badge IS NOT NULL)일 때만 발동 —
--       special_badge를 아예 건드리지 않는 절대다수의 정상 등록은
--       트리거 자체가 실행되지 않는다.
--     - UPDATE: WHEN (OLD.special_badge IS DISTINCT FROM NEW.special_badge)
--       일 때만 발동 — 이름 변경/소유권 이전/성장 Step 변경 등
--       special_badge를 건드리지 않는 기존 모든 수정 경로는 영향 없음.
--   선례: representative_character_setup.sql의
--   clear_representative_character_if_disqualified 트리거와 동일하게
--   "BEFORE 트리거로 DB 레벨에서 항상 검증" 패턴을 따른다.
-- ============================================================


-- ── 1. 컬럼 추가 ────────────────────────────────────────────
-- 표시 문구/CSS 클래스가 아니라 안정적인 key만 저장한다. 프론트 매핑은
-- pages/character.html의 SPECIAL_BADGE_MAP에서 처리
-- (specieslab_collab → "종족연구소 콜라보").
ALTER TABLE public.characters
ADD COLUMN IF NOT EXISTS special_badge text;

COMMENT ON COLUMN public.characters.special_badge IS
'운영자(admin) 전용 특별 분류 뱃지 key (예: specieslab_collab). 일반 유저/staff는 등록·수정 UI로도, 직접 API 호출로도 값을 넣거나 바꿀 수 없고, INSERT/UPDATE 모두 trg_guard_characters_special_badge_* 트리거로 admin 브라우저 요청 또는 JWT 없는 운영 DB 실행만 허용된다. 표시 문구/CSS는 DB에 저장하지 않고 character.html의 SPECIAL_BADGE_MAP에서 key→문구로 매핑.';


-- ── 2. 변경 가드 함수 — INSERT/UPDATE 공용 ─────────────────
CREATE OR REPLACE FUNCTION public.guard_characters_special_badge()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_caller_role text;
BEGIN
  -- auth.uid()가 NULL이면 JWT 없는 요청(Supabase SQL Editor, 서비스 롤
  -- 마이그레이션/백필 스크립트 등 운영자 직접 실행) — 그대로 통과시킨다.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_caller_role := (auth.jwt() -> 'app_metadata'::text) ->> 'role'::text;

  -- admin 브라우저 요청은 항상 허용 (staff 포함 그 외 전부 차단)
  IF v_caller_role = 'admin' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.special_badge IS NOT NULL THEN
      RAISE EXCEPTION '특별 분류 뱃지는 관리자만 지정할 수 있습니다.';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.special_badge IS DISTINCT FROM OLD.special_badge THEN
      RAISE EXCEPTION '특별 분류 뱃지는 관리자만 변경할 수 있습니다.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_characters_special_badge() FROM PUBLIC;


-- ── 3. INSERT 가드 트리거 ────────────────────────────────────
-- special_badge를 채워서 INSERT하려는 시도에만 발동. special_badge를
-- 아예 지정하지 않는 정상 등록(character-register.html 등 사실상 전부)은
-- 트리거가 실행조차 되지 않아 기존 등록 기능에 영향이 없다.
DROP TRIGGER IF EXISTS trg_guard_characters_special_badge_insert ON public.characters;

CREATE TRIGGER trg_guard_characters_special_badge_insert
BEFORE INSERT ON public.characters
FOR EACH ROW
WHEN (NEW.special_badge IS NOT NULL)
EXECUTE FUNCTION public.guard_characters_special_badge();


-- ── 4. UPDATE 가드 트리거 ────────────────────────────────────
-- special_badge 값이 실제로 바뀌는 UPDATE에만 발동. 이 컬럼을 건드리지
-- 않는 기존 모든 수정 경로(이름 변경, 소유권 이전, 성장 Step 변경 등)는
-- 이 트리거의 영향을 전혀 받지 않는다.
DROP TRIGGER IF EXISTS trg_guard_characters_special_badge_update ON public.characters;

CREATE TRIGGER trg_guard_characters_special_badge_update
BEFORE UPDATE OF special_badge ON public.characters
FOR EACH ROW
WHEN (OLD.special_badge IS DISTINCT FROM NEW.special_badge)
EXECUTE FUNCTION public.guard_characters_special_badge();

-- 기존 이름의 통합 트리거가 남아있을 수 있으므로(이전 리비전) 정리
DROP TRIGGER IF EXISTS trg_guard_characters_special_badge ON public.characters;


-- ── 5. characters_public 뷰 — 원본 정의 그대로 + special_badge만 끝에 추가
-- 레포에서 characters_public을 정의하는 곳은 supabase/character_contact_privacy.sql
-- 딱 한 곳뿐이며(2026-08-14 작성, 이후 재정의된 적 없음 — 이 SQL 작성 전
-- 저장소 전체를 재검색해 확인함), ALTER VIEW나 security_invoker/
-- security_barrier 옵션, 별도 필터 조건도 없다. 아래는 그 정의를 컬럼
-- 순서/내용 그대로 유지하고 맨 마지막에 special_badge 한 줄만 추가한
-- 것이다(연락처 3종 제외 + designer_external의 contact 키 제거 로직 등
-- 기존 가공 로직은 전혀 건드리지 않음).
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
  c.special_badge
FROM public.characters c;

GRANT SELECT ON public.characters_public TO anon, authenticated;

COMMENT ON VIEW public.characters_public IS
'characters의 공개 안전 버전. owner_contact/designer_contact 제외, designer_external은 각 원소에서 contact 키를 제거해 이름만 남긴다. special_badge(운영자 전용 특별 분류 뱃지 key)도 읽기 전용으로 포함. 연락처가 필요한 본인/관리자 편집 화면은 get_character_for_edit() RPC를 사용한다.';


-- ── 6. 적용 확인 ─────────────────────────────────────────
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'characters'
  AND column_name = 'special_badge';

SELECT tgname, tgrelid::regclass, tgenabled
FROM pg_catalog.pg_trigger
WHERE tgname IN (
  'trg_guard_characters_special_badge_insert',
  'trg_guard_characters_special_badge_update'
);


-- ============================================================
-- 사용 예시 (운영자가 Supabase SQL Editor에서 직접 실행 — JWT 없음, 항상 허용)
-- ============================================================
-- 지정:
--   UPDATE public.characters
--   SET special_badge = 'specieslab_collab'
--   WHERE id = 1234;
--
-- 해제:
--   UPDATE public.characters
--   SET special_badge = NULL
--   WHERE id = 1234;
