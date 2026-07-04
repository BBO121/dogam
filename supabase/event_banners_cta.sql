-- =============================================
-- event_banners CTA(문구 강조) 컬럼 추가
-- event_banners_setup.sql을 이미 실행한 경우에만 필요
-- Supabase Dashboard > SQL Editor에서 1회 실행
-- =============================================

ALTER TABLE public.event_banners
  ADD COLUMN IF NOT EXISTS show_cta BOOLEAN DEFAULT false;

-- cta_text가 없으면 우선 nullable로 추가
ALTER TABLE public.event_banners
  ADD COLUMN IF NOT EXISTS cta_text TEXT DEFAULT '자세히 보기 ▶';

-- 기존 데이터의 NULL/빈 문자열을 기본 문구로 보정 (NOT NULL 제약 추가 전 필수)
UPDATE public.event_banners
  SET cta_text = '자세히 보기 ▶'
  WHERE cta_text IS NULL OR btrim(cta_text) = '';

-- 기본값을 최신 문구로 갱신 + NOT NULL 제약 적용
ALTER TABLE public.event_banners
  ALTER COLUMN cta_text SET DEFAULT '자세히 보기 ▶';

ALTER TABLE public.event_banners
  ALTER COLUMN cta_text SET NOT NULL;
