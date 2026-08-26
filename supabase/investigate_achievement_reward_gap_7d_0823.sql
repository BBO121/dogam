-- ============================================================
-- [조사 전용] 업적 달성 후 보상/알림 후속처리 누락 — 최근 7일 전수 조사
-- 작성일: 2026-08-23
-- 배경: 리엔의 gong_o_visit_20 사례 — user_achievements INSERT는 성공했으나
--       currency_logs / notifications가 모두 생성되지 않음.
--       gong_o_visit_5(같은 계정, 38초 전)는 정상 처리됨 → 간헐적 후속처리 누락.
--
-- 전부 SELECT (조회) 전용입니다. INSERT/UPDATE/DELETE 없음.
-- Supabase SQL Editor에서 위에서부터 순서대로 실행하세요.
-- ============================================================


-- ── A. 달성은 됐는데 reward log(currency_logs)가 없는 경우 ────
-- note = achievements.name 매칭 + unlocked_at 전후 시간창(-2분~+10분)으로 오탐 최소화
SELECT
  ua.user_id,
  COALESCE(u.raw_user_meta_data->>'display_name',
           u.raw_user_meta_data->>'nickname')          AS nickname,
  a.code                                                AS achievement_code,
  a.name                                                AS achievement_name,
  ua.unlocked_at,
  CASE WHEN a.is_hidden THEN 10 ELSE 5 END              AS expected_reward,
  EXISTS (
    SELECT 1
    FROM public.currency_logs cl
    WHERE cl.user_id = ua.user_id
      AND cl.type    = 'achievement_reward'
      AND cl.source  = 'achievement'
      AND cl.note    = a.name
      AND cl.created_at BETWEEN ua.unlocked_at - INTERVAL '2 minutes'
                             AND ua.unlocked_at + INTERVAL '10 minutes'
  )                                                      AS reward_log_exists
FROM public.user_achievements ua
JOIN public.achievements a ON a.code = ua.achievement_code
JOIN auth.users u          ON u.id  = ua.user_id
WHERE ua.unlocked_at >= now() - INTERVAL '7 days'
ORDER BY ua.unlocked_at DESC;

-- A-1. 위 쿼리에서 누락 건만 필터 (missing-only)
-- WHERE 절 끝에 아래를 추가해서 실행:
--   AND NOT EXISTS ( ...위와 동일한 서브쿼리... )
-- 또는 A 전체를 CTE로 감싸 reward_log_exists = false 만 필터링해도 됨.


-- ── B. 달성은 됐는데 달성 알림 / 보상 알림이 없는 경우 ────────
-- 달성 알림: type='achievement', link='achievements.html', message='[업적명] 업적을 달성했습니다.'
-- 보상 알림: type='achievement', link='my-wallet.html',   message에 '연구기록 +' 포함
SELECT
  ua.user_id,
  COALESCE(u.raw_user_meta_data->>'display_name',
           u.raw_user_meta_data->>'nickname')          AS nickname,
  a.code                                                AS achievement_code,
  a.name                                                AS achievement_name,
  ua.unlocked_at,
  EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = ua.user_id
      AND n.type    = 'achievement'
      AND n.link    = 'achievements.html'
      AND n.message = '[' || a.name || '] 업적을 달성했습니다.'
      AND n.created_at BETWEEN ua.unlocked_at - INTERVAL '2 minutes'
                            AND ua.unlocked_at + INTERVAL '5 minutes'
  )                                                      AS achievement_notification_exists,
  EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = ua.user_id
      AND n.type    = 'achievement'
      AND n.link    = 'my-wallet.html'
      AND n.message LIKE '업적 보상으로 연구기록 +%를 획득했습니다!'
      AND n.created_at BETWEEN ua.unlocked_at - INTERVAL '2 minutes'
                            AND ua.unlocked_at + INTERVAL '10 minutes'
  )                                                      AS reward_notification_exists
FROM public.user_achievements ua
JOIN public.achievements a ON a.code = ua.achievement_code
JOIN auth.users u          ON u.id  = ua.user_id
WHERE ua.unlocked_at >= now() - INTERVAL '7 days'
ORDER BY ua.unlocked_at DESC;


-- ── C. [검증용] 리엔의 두 사례가 A/B 쿼리에서 정확히 구분되는지 확인 ──
-- gong_o_visit_5  → reward_log_exists = true,  두 notification 모두 true 여야 함
-- gong_o_visit_20 → reward_log_exists = false, 두 notification 모두 false 여야 함
-- (위 A, B 쿼리에 아래 WHERE 조건을 추가해서 실행)
--   AND ua.user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
--   AND a.code IN ('gong_o_visit_5', 'gong_o_visit_20')


-- ── D. [규모 집계] 업적 코드별 / 날짜별 누락 건수 요약 ─────────
WITH recent AS (
  SELECT
    ua.user_id,
    a.code,
    a.name,
    ua.unlocked_at,
    EXISTS (
      SELECT 1 FROM public.currency_logs cl
      WHERE cl.user_id = ua.user_id
        AND cl.type    = 'achievement_reward'
        AND cl.source  = 'achievement'
        AND cl.note    = a.name
        AND cl.created_at BETWEEN ua.unlocked_at - INTERVAL '2 minutes'
                               AND ua.unlocked_at + INTERVAL '10 minutes'
    ) AS reward_log_exists
  FROM public.user_achievements ua
  JOIN public.achievements a ON a.code = ua.achievement_code
  WHERE ua.unlocked_at >= now() - INTERVAL '7 days'
)
SELECT
  code,
  DATE(unlocked_at)                              AS unlocked_date,
  COUNT(*)                                        AS unlocked_count,
  COUNT(*) FILTER (WHERE NOT reward_log_exists)   AS missing_reward_count,
  COUNT(DISTINCT user_id) FILTER (WHERE NOT reward_log_exists) AS affected_users
FROM recent
GROUP BY code, DATE(unlocked_at)
ORDER BY missing_reward_count DESC, unlocked_date DESC;


-- ── E. [규모 집계] 영향받은 유저 전체 목록 (복구 대상 후보) ────
WITH recent AS (
  SELECT
    ua.user_id,
    a.code,
    a.name,
    ua.unlocked_at,
    CASE WHEN a.is_hidden THEN 10 ELSE 5 END AS expected_reward,
    EXISTS (
      SELECT 1 FROM public.currency_logs cl
      WHERE cl.user_id = ua.user_id
        AND cl.type    = 'achievement_reward'
        AND cl.source  = 'achievement'
        AND cl.note    = a.name
        AND cl.created_at BETWEEN ua.unlocked_at - INTERVAL '2 minutes'
                               AND ua.unlocked_at + INTERVAL '10 minutes'
    ) AS reward_log_exists
  FROM public.user_achievements ua
  JOIN public.achievements a ON a.code = ua.achievement_code
  WHERE ua.unlocked_at >= now() - INTERVAL '7 days'
)
SELECT
  user_id,
  COUNT(*) FILTER (WHERE NOT reward_log_exists)                    AS missing_count,
  SUM(expected_reward) FILTER (WHERE NOT reward_log_exists)        AS total_owed_research_records,
  array_agg(code) FILTER (WHERE NOT reward_log_exists)             AS missing_codes
FROM recent
GROUP BY user_id
HAVING COUNT(*) FILTER (WHERE NOT reward_log_exists) > 0
ORDER BY missing_count DESC;
