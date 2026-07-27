-- ============================================
-- characters.designer_external 컬럼 추가
-- 작성일: 2026-07-27
-- 목적:
-- 외부 디자이너를 문자열로 합쳐 저장한 뒤 split(' / ')로
-- 재파싱하던 방식을 폐지합니다.
--
-- 외부 디자이너는 jsonb 배열의 항목 단위로 저장합니다.
-- 예: [{"name": "이름", "contact": "연락처"}]
--
-- 연구소 디자이너는 designer_user_ids(uuid[])로 식별하며,
-- designer_nickname은 표시용 캐시 문자열로만 사용하고
-- 디자이너 구분이나 복원 목적으로 재파싱하지 않습니다.
-- ============================================

ALTER TABLE public.characters
ADD COLUMN IF NOT EXISTS designer_external jsonb
NOT NULL
DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.characters.designer_external IS
'외부 디자이너 목록. [{"name": "이름", "contact": "연락처"}, ...] 형태. 이름에 "/"가 포함되어도 항목 단위로 그대로 보존하며 문자열을 split하여 파싱하지 않습니다.';

-- 배열 이외의 잘못된 JSON 저장 방지
ALTER TABLE public.characters
DROP CONSTRAINT IF EXISTS characters_designer_external_is_array;

ALTER TABLE public.characters
ADD CONSTRAINT characters_designer_external_is_array
CHECK (jsonb_typeof(designer_external) = 'array');