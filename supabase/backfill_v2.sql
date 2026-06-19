-- ══════════════════════════════════════════════
--  누적 업적 백필 v2
--  이미 조건을 충족한 유저에게 소급 지급
--  supabase_counter_setup.sql 실행 후 실행하세요.
-- ══════════════════════════════════════════════

-- ── species_3: 종족 3개 이상 보유 ─────────────
INSERT INTO user_achievements (user_id, achievement_code)
SELECT owner_user_id, 'species_3'
FROM (
  SELECT owner_user_id, COUNT(*) AS cnt
  FROM species
  WHERE owner_user_id IS NOT NULL
  GROUP BY owner_user_id
  HAVING COUNT(*) >= 3
) sub
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- ── chars_10/30/50/100: 내 종족 개체 누적 ──────
-- (내 모든 종족의 개체 수 합산 기준)
WITH char_counts AS (
  SELECT s.owner_user_id, COUNT(c.id) AS cnt
  FROM species s
  JOIN characters c ON c.species_name = s.name
  WHERE s.owner_user_id IS NOT NULL
  GROUP BY s.owner_user_id
)
INSERT INTO user_achievements (user_id, achievement_code)
SELECT owner_user_id, 'chars_10'  FROM char_counts WHERE cnt >= 10
UNION ALL
SELECT owner_user_id, 'chars_30'  FROM char_counts WHERE cnt >= 30
UNION ALL
SELECT owner_user_id, 'chars_50'  FROM char_counts WHERE cnt >= 50
UNION ALL
SELECT owner_user_id, 'chars_100' FROM char_counts WHERE cnt >= 100
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- ── bug_report_3/10: 버그 리포트 누적 ──────────
WITH bug_counts AS (
  SELECT user_id, COUNT(*) AS cnt
  FROM bug_reports
  WHERE user_id IS NOT NULL
  GROUP BY user_id
)
INSERT INTO user_achievements (user_id, achievement_code)
SELECT user_id, 'bug_report_3'  FROM bug_counts WHERE cnt >= 3
UNION ALL
SELECT user_id, 'bug_report_10' FROM bug_counts WHERE cnt >= 10
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- ── adoption_10/20/30: 분양 완료 누적 ──────────
-- 기준: adoptions.status = '완료' AND user_id = 분양자
WITH adoption_counts AS (
  SELECT user_id, COUNT(*) AS cnt
  FROM adoptions
  WHERE user_id IS NOT NULL AND status = '완료'
  GROUP BY user_id
)
INSERT INTO user_achievements (user_id, achievement_code)
SELECT user_id, 'adoption_10' FROM adoption_counts WHERE cnt >= 10
UNION ALL
SELECT user_id, 'adoption_20' FROM adoption_counts WHERE cnt >= 20
UNION ALL
SELECT user_id, 'adoption_30' FROM adoption_counts WHERE cnt >= 30
ON CONFLICT (user_id, achievement_code) DO NOTHING;

-- ── 업적 도입 요약 알림 (유저당 1개) ────────────
-- Step 2 + backfill_v2 실행 완료 후 마지막에 실행
-- 업적이 1개 이상인 유저에게만 생성
INSERT INTO notifications (user_nickname, type, message, link)
SELECT
  COALESCE(
    u.raw_user_meta_data->>'display_name',
    u.raw_user_meta_data->>'nickname'
  ) AS user_nickname,
  'achievement' AS type,
  '업적 시스템이 도입됐어요! 그동안의 활동 기록을 바탕으로 획득한 업적이 등록되었습니다. 확인해보세요.' AS message,
  'achievements.html' AS link
FROM user_achievements ua
JOIN auth.users u ON u.id = ua.user_id
WHERE COALESCE(
    u.raw_user_meta_data->>'display_name',
    u.raw_user_meta_data->>'nickname'
  ) IS NOT NULL
GROUP BY u.id, u.raw_user_meta_data
HAVING COUNT(ua.achievement_code) >= 1;
