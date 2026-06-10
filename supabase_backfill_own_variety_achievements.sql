-- ══════════════════════════════════════════════
--  own_variety 업적 백필
--  전체 유저 대상 — 현재 소유 개체 기준으로 일괄 수여
--  Supabase SQL Editor에서 실행하세요.
-- ══════════════════════════════════════════════

-- 유저별 고유 종족 수 집계 후 조건에 맞는 업적 삽입
-- ON CONFLICT DO NOTHING → 이미 받은 업적은 중복 삽입하지 않음

WITH variety AS (
  SELECT
    owner_user_id,
    COUNT(DISTINCT species_name)::INT AS species_count
  FROM characters
  WHERE owner_user_id    IS NOT NULL
    AND owner_is_offsite = false
    AND species_name     IS NOT NULL
  GROUP BY owner_user_id
)
INSERT INTO user_achievements (user_id, achievement_code)
SELECT v.owner_user_id, a.code
FROM variety v
JOIN (VALUES
  (5,  'own_variety_5'),
  (10, 'own_variety_10'),
  (20, 'own_variety_20')
) AS a(threshold, code) ON v.species_count >= a.threshold
ON CONFLICT (user_id, achievement_code) DO NOTHING;
