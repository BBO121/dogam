-- ══════════════════════════════════════════════
--  badges 테이블 RLS: 전체 공개 읽기 허용
--  기존 코드는 user_badges → badges FK 조인으로만 접근해
--  RLS 없이도 동작했으나, 직접 SELECT 시 정책 필요
-- ══════════════════════════════════════════════

-- RLS 활성화 (이미 활성화된 경우 무시됨)
ALTER TABLE badges ENABLE ROW LEVEL SECURITY;

-- 뱃지 목록은 비로그인 포함 누구나 읽을 수 있도록 허용
CREATE POLICY "badges_public_read"
  ON badges
  FOR SELECT
  USING (true);
