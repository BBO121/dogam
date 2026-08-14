-- ============================================
-- 개인정보 정비 3개 SQL 실행 후 재검증에서 발견된 문제 패치
-- 작성일: 2026-08-15 / 수정: 2026-08-15 (트랜잭션 + search_path='' 반영)
--
-- ⚠️ 아직 실행하지 마세요 — anon 키로 라이브 재검증한 결과 발견된 문제들입니다.
--
-- [문제 A] characters/character_gallery 원본 테이블의 컬럼 단위 REVOKE가
-- 전혀 작동하지 않았습니다. anon 키로 직접 확인:
--   GET /rest/v1/characters?select=owner_contact,designer_contact,designer_external
--   → HTTP 200, 값 그대로 반환됨(REVOKE가 무효화된 상태)
--
-- 원인: PostgreSQL에서 컬럼 단위 권한과 테이블 단위 권한은 "합집합"으로
-- 작동합니다. characters/character_gallery는 애초에 Supabase가 테이블 생성 시
-- anon/authenticated에게 테이블 레벨 GRANT SELECT ON table TO role을 이미
-- 부여해둔 상태였던 것으로 보이고, 컬럼 단위 REVOKE만으로는 이를 이기지
-- 못합니다.
--
-- 해결: 테이블 레벨 SELECT를 완전히 REVOKE한 뒤, 안전한 컬럼만 컬럼 단위로
-- 다시 GRANT합니다. anon 키로 실제 라이브 전체 컬럼 목록을 직접 확인해서
-- (레포 코드만으로 추정했던 것보다 정확함) 아래 목록을 작성했습니다.
--
-- characters_public / character_gallery_public 뷰, get_character_for_edit()는
-- 정상 작동 확인됐습니다(뷰는 뷰 소유자 권한으로 원본을 읽으므로 이 REVOKE와
-- 무관하게 계속 정상 동작합니다).
--
-- [문제 B] get_character_for_edit() / delete_user()가 anon 키로도 실행됩니다
-- (최종 결과는 함수 내부 권한 체크로 막혀서 안전하지만, GRANT 설계 의도와는
-- 다릅니다). REVOKE ALL ... FROM PUBLIC만으로는 anon이라는 구체적 role에
-- 이미 자동으로 부여된 EXECUTE를 지우지 못하는 것으로 보여, anon을 명시적으로
-- REVOKE 대상에 넣습니다. 이 두 함수는 본문을 재생성하지 않고(이번 패치
-- 대상이 아님) 권한만 조정합니다.
--
-- [문제 C] resolve_users_by_identifiers() / resolve_users_by_ids()가 anon 키로
-- 호출 시 PGRST202(스키마에 함수 없음) 404가 났습니다 — 라이브에 함수 자체가
-- 없는 것으로 보입니다. 이 패치에서 다시 생성합니다.
--
-- [2026-08-15 뽀 검토 반영]
-- 1) 패치 전체를 BEGIN/COMMIT 트랜잭션으로 묶었습니다. 특히 재생성하는
--    SECURITY DEFINER 함수는 CREATE 직후 같은 트랜잭션 안에서 REVOKE/GRANT까지
--    처리해서, PostgreSQL DDL은 커밋 전까지 다른 세션에 보이지 않으므로
--    "생성됐지만 아직 권한이 안 좁혀진" 창(window)이 원천적으로 없습니다.
--    중간에 에러가 나면 전체가 롤백되어 "일부만 적용된 상태"도 방지됩니다
--    (문제 C가 애초에 이런 식으로 생겼을 가능성에 대한 대응이기도 합니다).
-- 2) resolve_users_by_identifiers() / resolve_users_by_ids() — Supabase
--    권장 패턴에 맞춰 SET search_path = ''로 바꾸고, 참조하는 모든 객체를
--    schema-qualified 했습니다:
--      - auth.users (원래도 이미 schema-qualified 상태였음)
--      - TRIM/LOWER/SPLIT_PART/UNNEST/ARRAY_LENGTH → pg_catalog.btrim 등으로 명시
--        (COALESCE/NULLIF/ANY/jsonb ->> 연산자는 SQL 표준 특수 구문이라
--         스키마 한정 대상이 아니고 search_path와 무관하게 항상 안전합니다 —
--         손대지 않았습니다)
--    본문 로직(매칭 조건, 정규화 방식, 반환 컬럼)은 전혀 바꾸지 않았습니다 —
--    함수 호출 방식(pg_catalog.btrim(x) ≡ TRIM(x))만 명시적으로 바뀐 것이라
--    동작은 기존과 완전히 동일합니다.
-- ============================================

BEGIN;

-- ============================================
-- A-1. characters — 테이블 레벨 REVOKE 후 안전 컬럼만 재부여
-- ============================================
-- PUBLIC까지 명시적으로 REVOKE합니다 — 테이블 레벨 권한이 anon/authenticated에게
-- 직접 부여된 게 아니라 PUBLIC 경유로 상속되고 있었을 가능성까지 방어(문제 A와
-- 동일한 함정: REVOKE 대상을 좁게 잡으면 다른 경로로 상속된 권한이 안 지워짐).
REVOKE SELECT ON public.characters FROM PUBLIC, anon, authenticated;

GRANT SELECT (
  id, created_at, name, species_name, owner_nickname, description, number,
  image_url, custom_fields, additional_images, custom_field_values,
  designer_nickname, is_sensitive, sensitive_note, category_id, category_label,
  category_color, char_categories, pending_transfer, char_sections,
  owner_user_id, owner_is_offsite, char_number, allow_free_adoption,
  allow_resale, allow_paid_adoption, allow_other_adoption, thumbnail_url,
  folder_id, owner_description, original_image_url, watermark_type,
  original_additional_images, designer_user_ids, representative_step_id,
  default_image_index
) ON public.characters TO anon, authenticated;

-- owner_contact, designer_contact, designer_external은 위 목록에 없으므로
-- anon/authenticated는 더 이상 어떤 방식으로도(select=*, 명시적 컬럼 지정 모두)
-- 이 3개 컬럼을 원본 테이블에서 가져올 수 없습니다.
-- (INSERT/UPDATE 권한은 이 REVOKE의 영향을 받지 않습니다 — SELECT만 다룹니다)


-- ============================================
-- A-2. character_gallery — 동일하게 테이블 레벨 REVOKE 후 안전 컬럼만 재부여
-- ============================================
REVOKE SELECT ON public.character_gallery FROM PUBLIC, anon, authenticated;

GRANT SELECT (
  id, character_id, uploaded_by, designer_user_ids, designer_nickname,
  category, description, image_url, thumbnail_url, created_at
) ON public.character_gallery TO anon, authenticated;

-- designer_external은 위 목록에 없으므로 원본 테이블에서 더 이상 노출되지 않습니다.


-- ============================================
-- B. 기존 함수(본문 재생성 없음) — anon EXECUTE 명시적 REVOKE
-- ============================================
REVOKE ALL ON FUNCTION public.get_character_for_edit(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_character_for_edit(bigint) TO authenticated;

REVOKE ALL ON FUNCTION public.delete_user(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user(UUID) TO authenticated;


-- ============================================
-- C-1. resolve_users_by_identifiers — 재생성 (search_path='' + schema-qualified)
--       CREATE 직후 같은 트랜잭션 안에서 바로 REVOKE/GRANT까지 처리합니다.
-- ============================================
CREATE OR REPLACE FUNCTION public.resolve_users_by_identifiers(p_identifiers text[])
RETURNS TABLE (
  matched_identifier text,
  id                  uuid,
  nickname            text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  SELECT raw_app_meta_data->>'role'
  INTO v_caller_role
  FROM auth.users WHERE id = auth.uid();

  IF auth.uid() IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '관리자만 실행할 수 있습니다.';
  END IF;

  IF p_identifiers IS NULL OR pg_catalog.array_length(p_identifiers, 1) IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT ident.x AS matched_identifier, sub.id, sub.nickname
  FROM pg_catalog.unnest(p_identifiers) AS ident(x)
  JOIN (
    SELECT
      u.id,
      NULLIF(pg_catalog.btrim(COALESCE(
        u.raw_user_meta_data->>'display_name',
        u.raw_user_meta_data->>'nickname',
        ''
      )), '') AS nickname,
      COALESCE(
        NULLIF(pg_catalog.btrim(u.raw_user_meta_data->>'login_id'), ''),
        pg_catalog.split_part(u.email, '@', 1)
      ) AS login_id
    FROM auth.users u
    WHERE u.deleted_at IS NULL
  ) sub
    ON pg_catalog.lower(sub.nickname) = pg_catalog.lower(pg_catalog.btrim(ident.x))
    OR pg_catalog.lower(sub.login_id) = pg_catalog.lower(pg_catalog.btrim(ident.x));
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_users_by_identifiers(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_users_by_identifiers(text[]) TO authenticated;


-- ============================================
-- C-2. resolve_users_by_ids — 재생성 (search_path='' + schema-qualified)
--       CREATE 직후 같은 트랜잭션 안에서 바로 REVOKE/GRANT까지 처리합니다.
-- ============================================
CREATE OR REPLACE FUNCTION public.resolve_users_by_ids(p_ids uuid[])
RETURNS TABLE (
  id       uuid,
  nickname text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT
    u.id,
    NULLIF(pg_catalog.btrim(COALESCE(
      u.raw_user_meta_data->>'display_name',
      u.raw_user_meta_data->>'nickname',
      ''
    )), '') AS nickname
  FROM auth.users u
  WHERE u.deleted_at IS NULL
    AND p_ids IS NOT NULL
    AND u.id = ANY(p_ids);
$$;

REVOKE ALL ON FUNCTION public.resolve_users_by_ids(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_users_by_ids(uuid[]) TO authenticated;


-- ============================================
-- D. PostgREST 스키마 캐시 강제 리로드
-- NOTIFY는 커밋 시점에 다른 세션(PostgREST)으로 전달되므로 트랜잭션 안에
-- 있어도 정상 동작합니다.
-- ============================================
NOTIFY pgrst, 'reload schema';

COMMIT;
