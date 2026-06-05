-- ══════════════════════════════════════════════
--  업적 시스템 셋업 SQL
--  Supabase SQL Editor에서 순서대로 실행하세요.
-- ══════════════════════════════════════════════


-- ── 1. 테이블 생성 ─────────────────────────────

CREATE TABLE IF NOT EXISTS achievements (
  id          SERIAL PRIMARY KEY,
  code        TEXT UNIQUE NOT NULL,
  name        TEXT NOT NULL,
  description TEXT,
  icon        TEXT,
  is_hidden   BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_achievements (
  id               SERIAL PRIMARY KEY,
  user_id          UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  achievement_code TEXT REFERENCES achievements(code) NOT NULL,
  unlocked_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, achievement_code)
);


-- ── 2. 기본 업적 데이터 ────────────────────────

INSERT INTO achievements (code, name, description) VALUES
  ('first_login',           '이곳은 종족연구소입니다!',  '처음 종족연구소에 로그인하세요.'),
  ('first_species',         '연구원 취직!',              '첫 종족을 등록하세요.'),
  ('first_character',       '생명 탄생!',                '첫 개체를 등록하세요.'),
  ('first_owned_character', '넌 내꺼야!',                '첫 내 개체를 가지세요.'),
  ('first_adoption',        '새로운 가족을 찾아서',       '첫 분양을 등록하세요.'),
  ('first_inquiry',         '문의 있습니다!',            '첫 문의를 작성하세요.'),
  ('first_bug_report',      '버그 사냥꾼',               '첫 버그 리포트를 작성하세요.')
ON CONFLICT (code) DO NOTHING;


-- ── 3. RLS 활성화 ──────────────────────────────

ALTER TABLE achievements      ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;


-- ── 4. RLS 정책 (재실행 시 중복 에러 방지) ──────

DROP POLICY IF EXISTS "achievements_select_all"       ON achievements;
DROP POLICY IF EXISTS "user_achievements_select_all"  ON user_achievements;
DROP POLICY IF EXISTS "user_achievements_insert_own"  ON user_achievements;

-- achievements: 누구나 읽기 가능
CREATE POLICY "achievements_select_all"
  ON achievements FOR SELECT USING (true);

-- user_achievements: 읽기 — 누구나 (프로필 공개 표시용)
CREATE POLICY "user_achievements_select_all"
  ON user_achievements FOR SELECT USING (true);

-- user_achievements: 쓰기 — UUID 기준, 본인만
CREATE POLICY "user_achievements_insert_own"
  ON user_achievements FOR INSERT
  WITH CHECK (user_id = auth.uid());


-- ══════════════════════════════════════════════
--  Backfill Step 1: 관리자 / 스태프 계정만
--  (테스트 확인 후 Step 2 실행)
-- ══════════════════════════════════════════════

-- first_login
INSERT INTO user_achievements (user_id, achievement_code, unlocked_at)
SELECT id, 'first_login', created_at
FROM auth.users
WHERE raw_user_meta_data->>'role' IN ('admin', 'staff')
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_species
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT s.owner_user_id, 'first_species'
FROM species s
JOIN auth.users u ON u.id = s.owner_user_id
WHERE s.owner_user_id IS NOT NULL
  AND u.raw_user_meta_data->>'role' IN ('admin', 'staff')
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_character (개체 등록 이력 — owner 기준 근사값)
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT c.owner_user_id, 'first_character'
FROM characters c
JOIN auth.users u ON u.id = c.owner_user_id
WHERE c.owner_user_id IS NOT NULL
  AND c.owner_is_offsite = false
  AND u.raw_user_meta_data->>'role' IN ('admin', 'staff')
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_owned_character
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT c.owner_user_id, 'first_owned_character'
FROM characters c
JOIN auth.users u ON u.id = c.owner_user_id
WHERE c.owner_user_id IS NOT NULL
  AND c.owner_is_offsite = false
  AND u.raw_user_meta_data->>'role' IN ('admin', 'staff')
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_adoption
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT a.user_id, 'first_adoption'
FROM adoptions a
JOIN auth.users u ON u.id = a.user_id
WHERE a.user_id IS NOT NULL
  AND u.raw_user_meta_data->>'role' IN ('admin', 'staff')
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_inquiry
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT i.user_id, 'first_inquiry'
FROM inquiries i
JOIN auth.users u ON u.id = i.user_id
WHERE i.user_id IS NOT NULL
  AND u.raw_user_meta_data->>'role' IN ('admin', 'staff')
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_bug_report
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT b.user_id, 'first_bug_report'
FROM bug_reports b
JOIN auth.users u ON u.id = b.user_id
WHERE b.user_id IS NOT NULL
  AND u.raw_user_meta_data->>'role' IN ('admin', 'staff')
ON CONFLICT (user_id, achievement_code) DO NOTHING;


-- ══════════════════════════════════════════════
--  Backfill Step 2: 전체 유저 (admin/staff 제외)
--  Step 1 테스트 완료 후 주석 해제하여 실행하세요.
-- ══════════════════════════════════════════════

/*

-- first_login
INSERT INTO user_achievements (user_id, achievement_code, unlocked_at)
SELECT id, 'first_login', created_at
FROM auth.users
WHERE raw_user_meta_data->>'role' NOT IN ('admin', 'staff')
   OR raw_user_meta_data->>'role' IS NULL
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_species
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT owner_user_id, 'first_species'
FROM species
WHERE owner_user_id IS NOT NULL
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_character (owner 기준 근사값)
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT owner_user_id, 'first_character'
FROM characters
WHERE owner_user_id IS NOT NULL
  AND owner_is_offsite = false
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_owned_character
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT owner_user_id, 'first_owned_character'
FROM characters
WHERE owner_user_id IS NOT NULL
  AND owner_is_offsite = false
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_adoption
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT user_id, 'first_adoption'
FROM adoptions
WHERE user_id IS NOT NULL
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_inquiry
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT user_id, 'first_inquiry'
FROM inquiries
WHERE user_id IS NOT NULL
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- first_bug_report
INSERT INTO user_achievements (user_id, achievement_code)
SELECT DISTINCT user_id, 'first_bug_report'
FROM bug_reports
WHERE user_id IS NOT NULL
ON CONFLICT (user_id, achievement_code) DO NOTHING;

*/
