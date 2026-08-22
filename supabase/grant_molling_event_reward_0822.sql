-- ============================================================
-- 몰링(Molling) 종족 프레임 & 스티커 이벤트 참여 보상 지급
-- 대상: 캐로로캐 (user_id = 4d442bfc-2d4d-4d24-86d4-02a0b85af563)
-- 지급: 연구기록 +50, 열쇠 +1
-- 작성일: 2026-08-22
--
-- 구성:
--   STEP 0. 대상 유저 확인 + 기존 지급 내역 확인 (읽기 전용, 반드시 먼저 확인)
--   STEP 1. 재화 지급 (idempotent, currency_logs.source로 중복 방지)
--   STEP 2. 알림 전송 (idempotent, notify_user_by_id 재사용)
--   STEP 3. 최종 결과 리포트 (읽기 전용)
--
-- 기존 구조 재사용 (grant_species_launch_reward_0815.sql과 동일 패턴):
--   - 재화 지급: user_wallets UPSERT + currency_logs 기록
--   - 알림: public.notify_user_by_id(uuid, text, text, text) RPC 그대로 호출
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- STEP 0 — 대상 유저 확인 + 기존 지급/알림 내역 확인 (읽기 전용)
-- 닉네임이 '캐로로캐'와 다르게 나오거나, 아래 결과에 이미 지급/알림
-- 내역이 있다면 STEP 1~2를 실행하기 전에 반드시 확인할 것.
-- ════════════════════════════════════════════════════════════
SELECT
  u.id,
  COALESCE(u.raw_user_meta_data->>'display_name', u.raw_user_meta_data->>'nickname') AS nickname,
  EXISTS (
    SELECT 1 FROM public.currency_logs
    WHERE user_id = u.id AND source = 'molling_event_reward_0822' AND currency = 'research_records'
  ) AS 연구기록_이미지급됨,
  EXISTS (
    SELECT 1 FROM public.currency_logs
    WHERE user_id = u.id AND source = 'molling_event_reward_0822' AND currency = 'keys'
  ) AS 열쇠_이미지급됨,
  EXISTS (
    SELECT 1 FROM public.notifications
    WHERE user_id = u.id AND type = 'molling_event_reward' AND link = 'shop.html'
  ) AS 알림_이미전송됨
FROM auth.users u
WHERE u.id = '4d442bfc-2d4d-4d24-86d4-02a0b85af563';


-- ════════════════════════════════════════════════════════════
-- STEP 1 — 재화 지급: 연구기록 +50, 열쇠 +1 (idempotent)
-- source='molling_event_reward_0822'로 이미 지급했는지 통화별로 확인 후 지급.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_user_id  uuid := '4d442bfc-2d4d-4d24-86d4-02a0b85af563';
  v_source   text := 'molling_event_reward_0822';
  v_note     text := '몰링 종족 프레임 & 스티커 이벤트 참여 감사 보상';
  v_new_rr   integer;
  v_new_keys integer;
BEGIN
  -- 연구기록 +50
  IF NOT EXISTS (
    SELECT 1 FROM public.currency_logs
    WHERE user_id = v_user_id AND source = v_source AND currency = 'research_records'
  ) THEN
    INSERT INTO public.user_wallets (user_id, research_records, keys, updated_at)
    VALUES (v_user_id, 50, 0, now())
    ON CONFLICT (user_id) DO UPDATE
      SET research_records = public.user_wallets.research_records + 50,
          updated_at       = now()
    RETURNING research_records INTO v_new_rr;

    INSERT INTO public.currency_logs
      (user_id, type, source, currency, amount, balance_after, note)
    VALUES
      (v_user_id, 'admin_grant', v_source, 'research_records', 50, v_new_rr, v_note);
  END IF;

  -- 열쇠 +1
  IF NOT EXISTS (
    SELECT 1 FROM public.currency_logs
    WHERE user_id = v_user_id AND source = v_source AND currency = 'keys'
  ) THEN
    INSERT INTO public.user_wallets (user_id, research_records, keys, updated_at)
    VALUES (v_user_id, 0, 1, now())
    ON CONFLICT (user_id) DO UPDATE
      SET keys       = public.user_wallets.keys + 1,
          updated_at = now()
    RETURNING keys INTO v_new_keys;

    INSERT INTO public.currency_logs
      (user_id, type, source, currency, amount, balance_after, note)
    VALUES
      (v_user_id, 'admin_grant', v_source, 'keys', 1, v_new_keys, v_note);
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════
-- STEP 2 — 알림 전송 (idempotent)
-- 기존 public.notify_user_by_id RPC 재사용. 동일 type+link로 이미 보낸
-- 알림이 있으면 SKIP.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_user_id uuid := '4d442bfc-2d4d-4d24-86d4-02a0b85af563';
  v_message text := '종족 프레임 & 스티커 이벤트 참여 감사의 뜻으로 소정의 재화를 지급해드립니다! 💌';
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE user_id = v_user_id AND type = 'molling_event_reward' AND link = 'shop.html'
  ) THEN
    PERFORM public.notify_user_by_id(
      p_user_id := v_user_id,
      p_type    := 'molling_event_reward',
      p_message := v_message,
      p_link    := 'shop.html'
    );
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════
-- STEP 3 — 최종 결과 리포트 (읽기 전용)
-- ════════════════════════════════════════════════════════════
SELECT
  w.user_id,
  w.research_records AS 현재_연구기록,
  w.keys             AS 현재_열쇠,
  (
    SELECT balance_after FROM public.currency_logs
    WHERE user_id = w.user_id AND source = 'molling_event_reward_0822' AND currency = 'research_records'
  ) AS 지급후_연구기록_잔액,
  (
    SELECT balance_after FROM public.currency_logs
    WHERE user_id = w.user_id AND source = 'molling_event_reward_0822' AND currency = 'keys'
  ) AS 지급후_열쇠_잔액,
  EXISTS (
    SELECT 1 FROM public.notifications
    WHERE user_id = w.user_id AND type = 'molling_event_reward' AND link = 'shop.html'
  ) AS 알림_전송됨
FROM public.user_wallets w
WHERE w.user_id = '4d442bfc-2d4d-4d24-86d4-02a0b85af563';
