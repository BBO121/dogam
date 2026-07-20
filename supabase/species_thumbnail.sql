-- ============================================
-- species 리스트용 썸네일(thumbnail_url) 컬럼 추가
-- 작성일: 2026-07-15
-- 목적: 리스트/메인/마이페이지 카드가 원본 image_url을
-- 그대로 다운로드하던 구조를 개선해 Cached Egress 사용량을 줄입니다.
-- ============================================

ALTER TABLE public.species
ADD COLUMN IF NOT EXISTS thumbnail_url text;

COMMENT ON COLUMN public.species.thumbnail_url IS
'리스트/카드용 소형 정사각 썸네일. 없으면 image_url을 대신 사용(하위 호환).';
