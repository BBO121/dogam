-- ============================================================
-- 업적 보상 누락분 복구 — 확인된 4건 (최근 7일 전수조사 결과)
-- 작성일: 2026-08-23
-- 근거: supabase/investigate_achievement_reward_gap_7d_0823.sql 실행 결과
--       (원인: award_achievement 도입 전 구 흐름의 achievements 재조회
--        단계 실패로 user_achievements만 생성되고 보상/알림 누락)
--
-- 대상 4건:
--   5df7b1f8-50a6-44b1-96ba-318df4f7c676 / gong_o_visit_20   (+10, 숨김업적)
--   7e5df3e1-7660-439f-a497-7926dc1c5b4d / own_variety_10    (+5)
--   ca160047-fddb-4fab-882f-2d1f3c5f8c33 / own_variety_20    (+10, 숨김업적)
--   e9341ded-658b-4b6b-a97c-e59ae1879b9b / first_notice      (+5)
--   합계: 30 연구기록
--
-- 안전장치 (하드코딩 지급 아님, 매 대상마다 재검증):
--   1) user_achievements에 실제 달성 기록이 있는지 재확인
--   2) currency_logs에 achievement_reward(source=achievement, note=업적명)가
--      이미 있으면 자동 SKIP → 이 스크립트를 몇 번 재실행해도 중복 지급 없음
--
-- 알림: 기존 "달성했습니다" 알림은 지금 와서 새로 만들면 뒤늦게 뜬금없이
--       뜨므로 재생성하지 않음. "보상 지급 오류로 누락된 보상을 지급했다"는
--       취지의 알림 1개만 신규 생성.
--
-- 실행 순서: STEP 0(미리보기, 읽기전용) → STEP 1(실제 지급) → STEP 2(재검증)
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- STEP 0 — 복구 대상 미리보기 (읽기 전용, 반드시 먼저 확인)
-- 이미지급됨=true인 행은 STEP 1에서 자동 SKIP된다.
-- ════════════════════════════════════════════════════════════
WITH targets (user_id, achievement_code) AS (
  VALUES
    ('5df7b1f8-50a6-44b1-96ba-318df4f7c676'::uuid, 'gong_o_visit_20'),
    ('7e5df3e1-7660-439f-a497-7926dc1c5b4d'::uuid, 'own_variety_10'),
    ('ca160047-fddb-4fab-882f-2d1f3c5f8c33'::uuid, 'own_variety_20'),
    ('e9341ded-658b-4b6b-a97c-e59ae1879b9b'::uuid, 'first_notice')
)
SELECT
  t.user_id,
  COALESCE(u.raw_user_meta_data->>'display_name',
           u.raw_user_meta_data->>'nickname')      AS nickname,
  t.achievement_code,
  a.name                                            AS achievement_name,
  ua.unlocked_at,
  (ua.user_id IS NOT NULL)                          AS 달성기록_존재,
  CASE WHEN a.is_hidden THEN 10 ELSE 5 END          AS 지급예정액,
  w.research_records                                AS 현재_연구기록,
  EXISTS (
    SELECT 1 FROM public.currency_logs cl
    WHERE cl.user_id = t.user_id
      AND cl.type    = 'achievement_reward'
      AND cl.source  = 'achievement'
      AND cl.note    = a.name
  )                                                  AS 이미지급됨
FROM targets t
LEFT JOIN public.achievements a       ON a.code = t.achievement_code
LEFT JOIN public.user_achievements ua ON ua.user_id = t.user_id AND ua.achievement_code = t.achievement_code
LEFT JOIN public.user_wallets w       ON w.user_id = t.user_id
LEFT JOIN auth.users u                ON u.id = t.user_id;


-- ════════════════════════════════════════════════════════════
-- STEP 1 — 실제 복구 지급 (idempotent)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  rec           RECORD;
  v_ach_name    text;
  v_is_hidden   boolean;
  v_amount      integer;
  v_new_balance integer;
  v_nickname    text;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      ('5df7b1f8-50a6-44b1-96ba-318df4f7c676'::uuid, 'gong_o_visit_20'),
      ('7e5df3e1-7660-439f-a497-7926dc1c5b4d'::uuid, 'own_variety_10'),
      ('ca160047-fddb-4fab-882f-2d1f3c5f8c33'::uuid, 'own_variety_20'),
      ('e9341ded-658b-4b6b-a97c-e59ae1879b9b'::uuid, 'first_notice')
    ) AS t(user_id, achievement_code)
  LOOP
    -- 안전장치 1: 실제 달성 기록 존재 확인
    IF NOT EXISTS (
      SELECT 1 FROM public.user_achievements
      WHERE user_id = rec.user_id AND achievement_code = rec.achievement_code
    ) THEN
      RAISE NOTICE '[SKIP-달성기록없음] user_id=%, code=%', rec.user_id, rec.achievement_code;
      CONTINUE;
    END IF;

    SELECT name, is_hidden INTO v_ach_name, v_is_hidden
    FROM public.achievements
    WHERE code = rec.achievement_code;

    IF NOT FOUND THEN
      RAISE NOTICE '[SKIP-업적정의없음] code=%', rec.achievement_code;
      CONTINUE;
    END IF;

    -- 안전장치 2: 이미 지급됐는지 재확인 (idempotent — 재실행 안전)
    IF EXISTS (
      SELECT 1 FROM public.currency_logs
      WHERE user_id = rec.user_id
        AND type    = 'achievement_reward'
        AND source  = 'achievement'
        AND note    = v_ach_name
    ) THEN
      RAISE NOTICE '[SKIP-이미지급됨] user_id=%, code=%', rec.user_id, rec.achievement_code;
      CONTINUE;
    END IF;

    v_amount := CASE WHEN v_is_hidden THEN 10 ELSE 5 END;

    SELECT COALESCE(raw_user_meta_data->>'display_name', raw_user_meta_data->>'nickname')
    INTO  v_nickname
    FROM  auth.users
    WHERE id = rec.user_id;

    -- 지갑 지급 — 행 없으면 생성, 있으면 증가
    INSERT INTO public.user_wallets (user_id, research_records, keys, updated_at)
    VALUES (rec.user_id, v_amount, 0, now())
    ON CONFLICT (user_id) DO UPDATE
      SET research_records = public.user_wallets.research_records + v_amount,
          updated_at       = now()
    RETURNING research_records INTO v_new_balance;

    -- 거래 로그 — 정상 보상과 동일한 type/source/note 형식으로 기록
    -- (추후 재조사 SQL이 "지급됨"으로 정확히 인식하도록 형식을 맞춤)
    INSERT INTO public.currency_logs (user_id, type, source, currency, amount, balance_after, note)
    VALUES (rec.user_id, 'achievement_reward', 'achievement', 'research_records', v_amount, v_new_balance, v_ach_name);

    -- 복구 전용 알림 (기존 "달성했습니다" 알림은 재생성하지 않음)
    INSERT INTO public.notifications (user_id, user_nickname, type, message, link)
    VALUES (
      rec.user_id,
      v_nickname,
      'achievement',
      '업적 보상 지급 오류로 누락된 연구기록 +' || v_amount || '이 지급되었습니다.',
      'my-wallet.html'
    );

    RAISE NOTICE '[지급완료] user_id=%, code=%, amount=%, new_balance=%', rec.user_id, rec.achievement_code, v_amount, v_new_balance;
  END LOOP;
END $$;


-- ════════════════════════════════════════════════════════════
-- STEP 2 — 복구 결과 재검증 (읽기 전용)
-- 4건 모두 이미지급됨=true, 현재_연구기록에 반영된 잔액이 보여야 함
-- ════════════════════════════════════════════════════════════
WITH targets (user_id, achievement_code) AS (
  VALUES
    ('5df7b1f8-50a6-44b1-96ba-318df4f7c676'::uuid, 'gong_o_visit_20'),
    ('7e5df3e1-7660-439f-a497-7926dc1c5b4d'::uuid, 'own_variety_10'),
    ('ca160047-fddb-4fab-882f-2d1f3c5f8c33'::uuid, 'own_variety_20'),
    ('e9341ded-658b-4b6b-a97c-e59ae1879b9b'::uuid, 'first_notice')
)
SELECT
  t.user_id,
  t.achievement_code,
  a.name                                   AS achievement_name,
  w.research_records                       AS 현재_연구기록,
  cl.amount                                AS 지급액,
  cl.created_at                            AS 지급시각,
  EXISTS (
    SELECT 1 FROM public.currency_logs c
    WHERE c.user_id = t.user_id AND c.type='achievement_reward' AND c.source='achievement' AND c.note = a.name
  )                                         AS 이미지급됨,
  EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.user_id = t.user_id AND n.type='achievement' AND n.message LIKE '업적 보상 지급 오류로%'
  )                                         AS 복구알림_전송됨
FROM targets t
LEFT JOIN public.achievements a  ON a.code = t.achievement_code
LEFT JOIN public.user_wallets w  ON w.user_id = t.user_id
LEFT JOIN public.currency_logs cl ON cl.user_id = t.user_id AND cl.type='achievement_reward' AND cl.source='achievement' AND cl.note = a.name;
