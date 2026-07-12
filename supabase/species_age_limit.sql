-- ============================================
-- species 연령 제한(age_limit) 컬럼 추가
-- 작성일: 2026-07-12
-- 종족연구소는 계속 전체 이용가 플랫폼이며,
-- age_limit은 성인 콘텐츠 허용 기능이 아니라
-- 종족주가 분양 대상의 최소 이용 연령을 표시하기 위한 값입니다.
-- 0 = 전체 이용 가능, 12/15/17/19 = 해당 연령 이상
-- ============================================

-- ── 1. 컬럼 추가 ─────────────────────────────
ALTER TABLE public.species
ADD COLUMN IF NOT EXISTS age_limit integer NOT NULL DEFAULT 0;

-- ── 2. 허용 값 제한 ──────────────────────────
ALTER TABLE public.species
DROP CONSTRAINT IF EXISTS species_age_limit_check;

ALTER TABLE public.species
ADD CONSTRAINT species_age_limit_check
CHECK (age_limit IN (0, 12, 15, 17, 19));

-- ── 3. 컬럼 설명 ─────────────────────────────
COMMENT ON COLUMN public.species.age_limit IS
'분양 최소 이용 연령. 0=전체 이용 가능, 12/15/17/19=해당 연령 이상';