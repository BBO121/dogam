-- ============================================================
-- [조사 전용] 업적 달성 보상/알림 미지급 버그 조사 SQL
-- 작성일: 2026-08-23
-- 제보: 유저 '리엔' (user_id: 5df7b1f8-50a6-44b1-96ba-318df4f7c676)
--       '공오 업적' 달성은 되지만 연구기록 보상/알림이 지급 안 됨
--
-- 전부 SELECT (조회) 전용입니다. INSERT/UPDATE/DELETE 없음.
-- Supabase SQL Editor에서 위에서부터 순서대로 실행하세요.
-- ============================================================


-- ── 0. 리엔 계정 기본 정보 (닉네임, 지갑 존재 여부) ─────────
-- 가설 A: user_wallets 행이 아예 없으면 grant_achievement_reward RPC가
--         UPDATE 0 rows → balance_after NULL → currency_logs NOT NULL 위반으로
--         전체 롤백(보상+RPC알림 모두 유실)될 수 있음.
-- 가설 B: user_metadata에 display_name/nickname이 없으면 awardAchievement()의
--         JS 쪽 "[업적명] 업적을 달성했습니다" 알림이 애초에 insert 자체를 스킵함.
SELECT
  u.id                                                            AS user_id,
  COALESCE(u.raw_user_meta_data->>'display_name',
           u.raw_user_meta_data->>'nickname')                     AS nickname,
  u.created_at                                                    AS user_created_at,
  w.user_id IS NOT NULL                                           AS has_wallet_row,
  w.research_records,
  w.keys,
  w.updated_at                                                    AS wallet_updated_at
FROM auth.users u
LEFT JOIN public.user_wallets w ON w.user_id = u.id
WHERE u.id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676';


-- ── 1. 리엔 — 공오 업적 4종 달성 여부 + 달성 시각 ────────────
SELECT
  a.code,
  a.name,
  a.is_hidden,
  CASE WHEN a.is_hidden THEN 10 ELSE 5 END          AS expected_reward_amount,
  ua.unlocked_at
FROM public.achievements a
LEFT JOIN public.user_achievements ua
  ON ua.achievement_code = a.code
  AND ua.user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
WHERE a.code IN ('gong_o_visit_1','gong_o_visit_5','gong_o_visit_20','gong_o_visit_100')
ORDER BY a.code;


-- ── 2. 리엔 — 공오 업적 관련 achievement_reward 재화 로그 존재 여부 ──
-- note 컬럼에 업적 "name"이 그대로 들어가는 구조 (grant_achievement_reward.sql 참고)
SELECT *
FROM public.currency_logs
WHERE user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
  AND type = 'achievement_reward'
  AND note IN (
    '안녕하세요! 연구소 마스코트 공오에요!',
    '또 오셨네요!',
    '제가 그렇게 궁금해요!?',
    '...그만 좀 와!!!!'
  )
ORDER BY created_at;


-- ── 3. 리엔 — 달성 시각 전후 ±10분 사이의 모든 재화 로그 ────────
-- (혹시 다른 achievement_reward가 이 시간대에 성공했는지, 실패 흔적이 있는지 대조용)
WITH gongo AS (
  SELECT MIN(unlocked_at) AS first_unlock, MAX(unlocked_at) AS last_unlock
  FROM public.user_achievements
  WHERE user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
    AND achievement_code IN ('gong_o_visit_1','gong_o_visit_5','gong_o_visit_20','gong_o_visit_100')
)
SELECT cl.*
FROM public.currency_logs cl, gongo
WHERE cl.user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
  AND cl.created_at BETWEEN gongo.first_unlock - INTERVAL '10 minutes'
                         AND gongo.last_unlock  + INTERVAL '10 minutes'
ORDER BY cl.created_at;


-- ── 4. 리엔 — 공오 업적 관련 알림 존재 여부 ────────────────────
SELECT *
FROM public.notifications
WHERE user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
  AND (
    message LIKE '%공오%'
    OR message LIKE '%연구기록%'
    OR link IN ('achievements.html', 'my-wallet.html')
  )
ORDER BY created_at DESC
LIMIT 30;


-- ── 5. 리엔 — 전체 업적 달성 이력 vs 보상 로그 vs 알림 대조 ────
-- 다른 업적은 정상 지급됐는지 확인 → 공오만의 문제인지, 리엔 계정 전체 문제인지 구분
SELECT
  a.code,
  a.name,
  a.is_hidden,
  ua.unlocked_at,
  cl.id            AS reward_log_id,
  cl.amount        AS reward_amount,
  cl.created_at    AS reward_at,
  (cl.id IS NOT NULL)  AS has_reward_log
FROM public.user_achievements ua
JOIN public.achievements a ON a.code = ua.achievement_code
LEFT JOIN public.currency_logs cl
  ON cl.user_id = ua.user_id
  AND cl.type = 'achievement_reward'
  AND cl.note = a.name
WHERE ua.user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
ORDER BY ua.unlocked_at;


-- ── 6. 리엔 — user_achievement_counters 상 gong_o_visit 카운터 값 ──
-- (실제 방문 횟수가 몇 번이었는지, 100 이상 찍혀서 4개 전부 동시에 트리거됐는지 확인)
SELECT *
FROM public.user_achievement_counters
WHERE user_id = '5df7b1f8-50a6-44b1-96ba-318df4f7c676'
  AND counter_key = 'gong_o_visit';


-- ============================================================
-- ── 7. [전수 확인] 최근 7일 — 업적 달성 vs 보상로그 vs 알림 대조 ──
-- 달성했는데 reward log가 없는 사례 / notification이 없는 사례를
-- 전체 유저 기준으로 찾아냄 (공오 업적만의 문제인지, 전체 문제인지 판별용)
-- ============================================================
SELECT
  ua.user_id,
  COALESCE(pu.raw_user_meta_data->>'display_name',
           pu.raw_user_meta_data->>'nickname')            AS nickname,
  a.code                                                   AS achievement_code,
  a.name                                                   AS achievement_name,
  a.is_hidden,
  CASE WHEN a.is_hidden THEN 10 ELSE 5 END                 AS expected_reward,
  ua.unlocked_at,
  cl.amount                                                AS actual_reward_amount,
  (cl.id IS NOT NULL)                                      AS has_reward_log,
  EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.user_id = ua.user_id
      AND n.created_at BETWEEN ua.unlocked_at - INTERVAL '5 minutes'
                            AND ua.unlocked_at + INTERVAL '10 minutes'
      AND n.type = 'achievement'
  )                                                         AS has_any_achievement_notification
FROM public.user_achievements ua
JOIN public.achievements a  ON a.code = ua.achievement_code
JOIN auth.users pu          ON pu.id  = ua.user_id
LEFT JOIN public.currency_logs cl
  ON cl.user_id = ua.user_id
  AND cl.type   = 'achievement_reward'
  AND cl.note   = a.name
WHERE ua.unlocked_at >= now() - INTERVAL '7 days'
ORDER BY ua.unlocked_at DESC;


-- ── 8. [전수 확인 요약] 위 결과를 업적 코드 기준으로 집계 ──────
-- 특정 업적 코드만 reward_log 누락률이 높다면 "그 업적만의 문제"
-- 여러 업적에 걸쳐 골고루 누락돼 있다면 "구조적 전체 문제"
WITH recent AS (
  SELECT
    ua.user_id,
    a.code,
    a.name,
    ua.unlocked_at,
    (cl.id IS NOT NULL) AS has_reward_log
  FROM public.user_achievements ua
  JOIN public.achievements a ON a.code = ua.achievement_code
  LEFT JOIN public.currency_logs cl
    ON cl.user_id = ua.user_id
    AND cl.type   = 'achievement_reward'
    AND cl.note   = a.name
  WHERE ua.unlocked_at >= now() - INTERVAL '7 days'
)
SELECT
  code,
  COUNT(*)                                   AS unlocked_count,
  COUNT(*) FILTER (WHERE has_reward_log)     AS rewarded_count,
  COUNT(*) FILTER (WHERE NOT has_reward_log) AS missing_reward_count
FROM recent
GROUP BY code
ORDER BY missing_reward_count DESC, unlocked_count DESC;


-- ── 9. [참고] 공오 업적 정의 vs 다른 최근 업적 정의 비교 ───────
-- reward/조건/코드 구조상 공오만 특별 취급되는 컬럼이 있는지 확인
-- (achievements 테이블에 reward_amount 같은 별도 컬럼이 없으므로
--  is_hidden 값만으로 5/10 결정됨 — 코드 로직과 동일한지 확인용)
SELECT code, name, description, icon, is_hidden, created_at
FROM public.achievements
ORDER BY created_at DESC
LIMIT 20;
