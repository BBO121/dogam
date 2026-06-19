-- ══════════════════════════════════════════════
--  badges 테이블에 is_obtainable 컬럼 추가
--  true  = 현재 획득 가능
--  false = 현재 획득 불가 (한정 뱃지 등)
-- ══════════════════════════════════════════════

ALTER TABLE badges
  ADD COLUMN IF NOT EXISTS is_obtainable boolean NOT NULL DEFAULT true;

-- 오픈베타 연구원 뱃지: 베타 기간 종료로 획득 불가
UPDATE badges SET is_obtainable = false WHERE code = 'beta';
