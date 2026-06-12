-- ══════════════════════════════════════════════
--  대표 업적 설정 기능 — user_profiles 컬럼 추가
--  Supabase SQL Editor에서 실행하세요.
-- ══════════════════════════════════════════════

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS featured_achievements JSONB DEFAULT '[]';
