-- ============================================================
-- [조사 전용] 업적 보상/알림 누락 — 전체 기간 전수 조사
-- 작성일: 2026-08-23
-- 배경: supabase/investigate_achievement_reward_gap_7d_0823.sql 로 최근 7일에서
--       4건 확인 후 복구(supabase/backfill_missing_achievement_rewards_0823.sql)
--       진행. 구조적 결함(client 4단계 순차 호출)은 award_achievement RPC
--       도입 이전부터 존재했으므로 7일 이전 데이터에도 누락 가능성이 있어
--       전체 기간으로 범위를 넓혀 조사한다.
--
-- 전부 SELECT (조회) 전용입니다. INSERT/UPDATE/DELETE 없음.
-- 이 결과는 자동 복구하지 않습니다 — 조회 후 별도로 판단합니다.
--
-- 오탐 최소화: type/source/note(업적명) 정확 일치 + user_id 일치를 기본으로
-- 하고, 시간차(created_at - unlocked_at)를 함께 노출해 육안으로도 이상 여부를
-- 재확인할 수 있게 함. 오래된 데이터는 achievements.name이 이후 개정
-- (예: achievements_v2.sql의 UPDATE)됐을 수 있어 note 매칭이 어긋날 수 있음 —
-- 결과에 이름 변경 이력이 의심되면 achievements_v2.sql / v3 / v4의 UPDATE문과
-- 대조해서 개별 확인할 것.
-- ============================================================


-- ── A. 달성은 됐는데 reward log(currency_logs)가 없는 경우 — 전체 기간 ──
-- 주의: grant_achievement_backfill.sql로 필백된 유저는 achievement_reward가
-- 아니라 achievement_backfill 타입 로그 1건(유저당 합산)으로 지급됐으므로,
-- 이 쿼리 기준으로는 그 유저의 "모든" 업적이 reward_log_exists=false로
-- 잡힌다. legacy_backfill_covered=true인 행은 실제 버그가 아니라
-- 필백으로 이미 정산된 유저이니 별도로 판단할 것(전수 합산 대상에서 제외 권장).
SELECT
  ua.user_id,
  COALESCE(u.raw_user_meta_data->>'display_name',
           u.raw_user_meta_data->>'nickname')          AS nickname,
  a.code                                                AS achievement_code,
  a.name                                                AS achievement_name,
  ua.unlocked_at,
  CASE WHEN a.is_hidden THEN 10 ELSE 5 END              AS expected_reward,
  cl.created_at                                         AS matched_reward_log_at,
  (cl.id IS NOT NULL)                                   AS reward_log_exists,
  EXISTS (
    SELECT 1 FROM public.currency_logs bl
    WHERE bl.user_id = ua.user_id AND bl.type = 'achievement_backfill'
  )                                                      AS legacy_backfill_covered
FROM public.user_achievements ua
JOIN public.achievements a ON a.code = ua.achievement_code
JOIN auth.users u          ON u.id  = ua.user_id
LEFT JOIN public.currency_logs cl
  ON cl.user_id = ua.user_id
  AND cl.type   = 'achievement_reward'
  AND cl.source = 'achievement'
  AND cl.note   = a.name
WHERE cl.id IS NULL   -- 누락 건만 표시 (전체를 보려면 이 줄을 지울 것)
ORDER BY ua.unlocked_at DESC;


-- ── B. 달성은 됐는데 알림이 없는 경우 — 전체 기간 ──────────────
SELECT
  ua.user_id,
  COALESCE(u.raw_user_meta_data->>'display_name',
           u.raw_user_meta_data->>'nickname')          AS nickname,
  a.code                                                AS achievement_code,
  a.name                                                AS achievement_name,
  ua.unlocked_at,
  EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.user_id = ua.user_id
      AND n.type    = 'achievement'
      AND n.link    = 'achievements.html'
      AND n.message = '[' || a.name || '] 업적을 달성했습니다.'
  )                                                      AS achievement_notification_exists,
  EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.user_id = ua.user_id
      AND n.type    = 'achievement'
      AND n.link    = 'my-wallet.html'
      AND (
        n.message LIKE '업적 보상으로 연구기록 +%를 획득했습니다!'
        OR n.message LIKE '업적 보상 지급 오류로 누락된 연구기록 +%이 지급되었습니다.'  -- 복구 알림도 인정
      )
  )                                                      AS reward_notification_exists,
  -- grant_achievement_backfill은 유저당 알림 1건으로 여러 업적을 합산 처리하므로
  -- 개별 업적 단위로는 매칭되지 않는다. 이 유저는 별도로 확인할 것.
  EXISTS (
    SELECT 1 FROM public.currency_logs bl
    WHERE bl.user_id = ua.user_id AND bl.type = 'achievement_backfill'
  )                                                      AS legacy_backfill_covered
FROM public.user_achievements ua
JOIN public.achievements a ON a.code = ua.achievement_code
JOIN auth.users u          ON u.id  = ua.user_id
ORDER BY ua.unlocked_at DESC;

-- B-1. 알림 누락만 필터링하려면 위 쿼리를 CTE로 감싸고 아래 조건 추가:
--   WHERE NOT achievement_notification_exists OR NOT reward_notification_exists


-- ── C. [규모 집계] 업적 코드별 / 연-월별 누락 건수 요약 (전체 기간) ──
WITH all_time AS (
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
    ) AS reward_log_exists
  FROM public.user_achievements ua
  JOIN public.achievements a ON a.code = ua.achievement_code
)
SELECT
  code,
  to_char(unlocked_at, 'YYYY-MM')                AS unlocked_month,
  COUNT(*)                                        AS unlocked_count,
  COUNT(*) FILTER (WHERE NOT reward_log_exists)   AS missing_reward_count
FROM all_time
GROUP BY code, to_char(unlocked_at, 'YYYY-MM')
HAVING COUNT(*) FILTER (WHERE NOT reward_log_exists) > 0
ORDER BY unlocked_month DESC, missing_reward_count DESC;


-- ── D. [규모 집계] 영향받은 유저 전체 목록 + 예상 총 미지급액 (전체 기간) ──
-- legacy_backfill_covered=true인 유저는 grant_achievement_backfill로 이미
-- 정산된 유저이니 total_owed_research_records를 그대로 신뢰하지 말고 별도 확인.
WITH all_time AS (
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
    ) AS reward_log_exists
  FROM public.user_achievements ua
  JOIN public.achievements a ON a.code = ua.achievement_code
)
SELECT
  user_id,
  COUNT(*) FILTER (WHERE NOT reward_log_exists)                AS missing_count,
  SUM(expected_reward) FILTER (WHERE NOT reward_log_exists)    AS total_owed_research_records,
  array_agg(code ORDER BY unlocked_at) FILTER (WHERE NOT reward_log_exists) AS missing_codes,
  array_agg(unlocked_at ORDER BY unlocked_at) FILTER (WHERE NOT reward_log_exists) AS missing_unlocked_at,
  EXISTS (
    SELECT 1 FROM public.currency_logs bl
    WHERE bl.user_id = all_time.user_id AND bl.type = 'achievement_backfill'
  )                                                              AS legacy_backfill_covered
FROM all_time
GROUP BY user_id
HAVING COUNT(*) FILTER (WHERE NOT reward_log_exists) > 0
ORDER BY missing_count DESC;
