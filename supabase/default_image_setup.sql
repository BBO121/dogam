-- ============================================
-- 대표/메인 이미지가 없을 때 사용할 연구소 기본 이미지 선택 기능
-- 작성일: 2026-08-14
--
-- 실제 이미지를 업로드하지 않아도 종족/개체가 기본 이미지(1~5) 중
-- 하나를 대표 이미지로 지정할 수 있도록 한다.
--
-- 실제 이미지(image_url)와 별개 컬럼이라 기존 로직과 충돌하지 않는다.
-- 우선순위(화면 렌더링 시): 실제 이미지 > default_image_index > id 기반 자동 fallback
--
-- 실제 이미지를 나중에 업로드해도 default_image_index 값은 보존한다.
-- (실제 이미지를 다시 삭제하면 기본 이미지로 돌아가도록 하기 위함)
-- ============================================

ALTER TABLE public.species
ADD COLUMN IF NOT EXISTS default_image_index smallint
  CHECK (default_image_index BETWEEN 1 AND 5);

COMMENT ON COLUMN public.species.default_image_index IS
'대표 이미지가 없을 때 사용할 연구소 기본 이미지 번호(1~5). NULL이면 미지정 — 화면에서는 종족 id 기반 자동 fallback을 사용한다. image_url이 있으면 이 값보다 항상 우선한다.';

ALTER TABLE public.characters
ADD COLUMN IF NOT EXISTS default_image_index smallint
  CHECK (default_image_index BETWEEN 1 AND 5);

COMMENT ON COLUMN public.characters.default_image_index IS
'메인 이미지가 없을 때 사용할 연구소 기본 이미지 번호(1~5, 3:4 버전). NULL이면 미지정 — 화면에서는 개체 id 기반 자동 fallback을 사용한다. image_url이 있으면 이 값보다 항상 우선한다.';
