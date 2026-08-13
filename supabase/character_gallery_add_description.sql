-- ============================================
-- character_gallery: description 컬럼 추가 (선택 입력)
-- 작성일: 2026-08-13
-- character_gallery_setup.sql을 이미 실행한 프로젝트에 적용.
-- CREATE TABLE IF NOT EXISTS는 기존 테이블에 컬럼을 추가해주지 않으므로 별도 ALTER 필요.
-- ============================================

ALTER TABLE public.character_gallery
  ADD COLUMN IF NOT EXISTS description text;
