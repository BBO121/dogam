-- ============================================
-- 개체(characters) 아티스트(크레딧) 필드 추가
-- 작성일: 2026-09-01 / 수정: 2026-09-01 (단일→다중 구조 변경, 재실행 안전하게 정리)
--
-- 목적:
--   개체 정보의 "디자이너"와 "소유주" 사이에 선택적인 "아티스트" 크레딧을 추가한다.
--   (개체 일러스트를 그린 사람. 단순 표시용 크레딧 — TOS / 프로필 링크 / 검색 /
--    권한 부여는 범위 밖.)
--
-- 구조(뽀 확인):
--   디자이너와 동일하게 "여러 명" 등록 가능. 연락처만 저장하지 않는다.
--     artist_user_ids  uuid[]  NULL  -- 연구소 회원들의 user id 배열 (프로필 링크용)
--     artist_external  jsonb   NULL  -- 외부 인물 목록 [{ "name": "..." }, ...] (contact 없음)
--     artist_nickname  text    NULL  -- 표시용 캐시 (" / "로 이어붙인 이름들)
--   셋 다 비어 있으면 아티스트 없음 → 화면에서 줄 자체를 만들지 않는다.
--   (designer_user_ids / designer_external / designer_nickname 과 같은 구조 —
--    designer_contact / designer_external.contact 에 해당하는 것만 없음)
--
-- ⚠️ 이 스크립트는 "단일 버전(artist_user_id text/uuid)"을 이미 한 번 실행했든,
--    아직 아무것도 실행 안 했든 양쪽 모두에서 안전하게 돌아가도록 작성됐다.
--    - 뷰를 먼저 DROP 하므로 CREATE OR REPLACE 의 "컬럼 이름 변경 불가" 오류가 안 난다.
--    - 예전 artist_user_id 컬럼이 있으면 값을 artist_user_ids 로 옮긴 뒤 제거한다.
--    - 전체를 트랜잭션으로 묶어 중간 실패 시 원상복구된다.
--
-- 실행 순서:
--   프론트엔드(character-register / character-edit)가 artist_user_ids /
--   artist_external / artist_nickname 을 저장 페이로드에 포함하므로, 컬럼이 없는
--   상태로 프론트를 먼저 배포하면 저장 시 400이 난다 → 이 SQL을 먼저(또는 함께) 실행.
-- ============================================

BEGIN;


-- ============================================
-- 0. characters_public 뷰를 먼저 내린다
--    (예전 artist_user_id 컬럼을 참조할 수 있고, 컬럼 목록 자체가 바뀌므로
--     CREATE OR REPLACE 로는 교체 불가 — DROP 후 재생성한다.
--     이 뷰에 의존하는 다른 DB 객체는 없다. 프론트는 트랜잭션이라 무중단.)
-- ============================================
DROP VIEW IF EXISTS public.characters_public;


-- ============================================
-- 1. 새 컬럼 추가 (백필 없음)
-- ============================================
ALTER TABLE public.characters
  ADD COLUMN IF NOT EXISTS artist_user_ids uuid[] NULL,
  ADD COLUMN IF NOT EXISTS artist_external jsonb  NULL,
  ADD COLUMN IF NOT EXISTS artist_nickname text   NULL;


-- ============================================
-- 2. 예전 단일 버전(artist_user_id) 잔재 정리
--    있으면 값을 artist_user_ids 로 이관한 뒤 컬럼 제거. 없으면 아무것도 안 함.
-- ============================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'characters' AND column_name = 'artist_user_id'
  ) THEN
    UPDATE public.characters
      SET artist_user_ids = ARRAY[artist_user_id]::uuid[]
      WHERE artist_user_id IS NOT NULL
        AND (artist_user_ids IS NULL OR cardinality(artist_user_ids) = 0);

    ALTER TABLE public.characters DROP COLUMN artist_user_id;
  END IF;
END $$;


-- ============================================
-- 3. 컬럼 코멘트
-- ============================================
COMMENT ON COLUMN public.characters.artist_user_ids IS
'개체 아티스트(일러스트 크레딧) 중 연구소 회원들의 user id 배열. 소유권/수정권한/종족주/디자이너 판별 로직에는 절대 포함하지 않는다(단순 크레딧).';

COMMENT ON COLUMN public.characters.artist_external IS
'개체 아티스트 중 사이트 밖 인물 목록. [{ "name": "..." }, ...] 형태. 디자이너와 달리 contact(연락처)는 저장하지 않는다.';

COMMENT ON COLUMN public.characters.artist_nickname IS
'개체 아티스트 표시용 캐시. 회원 닉네임 + 외부 이름을 " / "로 이어붙인 문자열. NULL/빈 문자열이면 상세 화면에서 "아티스트" 줄을 만들지 않는다. 재파싱하지 않는 표시용 캐시일 뿐이다.';


-- ============================================
-- 4. 원본 테이블 컬럼 단위 GRANT
--    privacy_fix_patch2.sql 에서 characters 는 테이블 레벨 SELECT를 REVOKE하고
--    안전 컬럼만 명시적으로 GRANT하는 방식으로 바뀌었다. 아티스트 크레딧 3개도
--    디자이너 크레딧(designer_user_ids 등)과 동일하게 공개 대상이다.
--    (아티스트는 contact가 없으므로 designer_external 처럼 REVOKE할 대상이 없다)
-- ============================================
GRANT SELECT (artist_user_ids, artist_external, artist_nickname)
  ON public.characters
  TO anon, authenticated;


-- ============================================
-- 5. characters_public 뷰 재생성
--    기존 라이브 정의(character_contact_privacy.sql + character_special_badge_setup.sql)
--    그대로 + 맨 끝에 artist_* 3컬럼만 추가.
--    연락처 3종 제외 / designer_external 의 contact 키 제거 로직은 그대로 유지.
--    artist_external 은 contact가 없으므로 가공 없이 그대로 노출한다.
-- ============================================
CREATE VIEW public.characters_public AS
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
  c.artist_nickname
FROM public.characters c;

GRANT SELECT ON public.characters_public TO anon, authenticated;

COMMENT ON VIEW public.characters_public IS
'characters의 공개 안전 버전. owner_contact/designer_contact 제외, designer_external은 각 원소에서 contact 키를 제거해 이름만 남긴다. special_badge(운영자 전용 특별 분류 뱃지 key), artist_user_ids/artist_external/artist_nickname(아티스트 크레딧 — contact 없음)도 읽기 전용으로 포함. 연락처가 필요한 본인/관리자 편집 화면은 get_character_for_edit() RPC를 사용한다.';


-- ============================================
-- 6. PostgREST 스키마 캐시 리로드
-- ============================================
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================
-- 참고: get_character_for_edit(bigint) 는 RETURNS SETOF public.characters +
--   본문이 SELECT * 라서 컬럼 추가 시 자동으로 artist_* 를 함께 반환한다.
--   재정의 불필요.
-- ============================================
