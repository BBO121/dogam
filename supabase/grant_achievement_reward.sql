-- ============================================================
-- [STEP 2] grant_achievement_reward
-- 업적 신규 획득 시 연구기록 지급 + currency_logs + notifications
-- 호출: sb.rpc('grant_achievement_reward', { p_achievement_code: code })
-- ============================================================

CREATE OR REPLACE FUNCTION public.grant_achievement_reward(
  p_achievement_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id     uuid;
  v_nickname    text;
  v_ach_name    text;
  v_is_hidden   boolean;
  v_amount      integer;
  v_new_balance integer;
BEGIN

  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'NOT_AUTHENTICATED'
    );
  END IF;

  -- 업적 보유 여부 확인
  IF NOT EXISTS (
    SELECT 1
    FROM user_achievements
    WHERE user_id         = v_user_id
      AND achievement_code = p_achievement_code
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'NOT_UNLOCKED'
    );
  END IF;

  -- 업적 이름 + is_hidden 조회
  SELECT name, is_hidden
  INTO   v_ach_name, v_is_hidden
  FROM   achievements
  WHERE  code = p_achievement_code;

  -- 중복 보상 방지 (같은 업적 이름으로 이미 지급 기록이 있으면 스킵)
  IF EXISTS (
    SELECT 1
    FROM currency_logs
    WHERE user_id = v_user_id
      AND type    = 'achievement_reward'
      AND note    = v_ach_name
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'ALREADY_REWARDED'
    );
  END IF;

  -- 지급액 결정
  v_amount := CASE WHEN v_is_hidden THEN 10 ELSE 5 END;

  -- 닉네임 조회 (알림 user_nickname 용 — 없어도 user_id로 알림 전달)
  SELECT COALESCE(
    raw_user_meta_data->>'display_name',
    raw_user_meta_data->>'nickname'
  )
  INTO  v_nickname
  FROM  auth.users
  WHERE id = v_user_id;

  -- 지갑 업데이트
  UPDATE user_wallets
  SET    research_records = research_records + v_amount,
         updated_at       = now()
  WHERE  user_id = v_user_id
  RETURNING research_records INTO v_new_balance;

  -- 거래 로그 기록
  INSERT INTO currency_logs (user_id, type, source, currency, amount, balance_after, note)
  VALUES (
    v_user_id,
    'achievement_reward',
    'achievement',
    'research_records',
    v_amount,
    v_new_balance,
    v_ach_name
  );

  -- 알림 생성 (user_id 기준 — 닉네임 없는 유저도 수신 가능)
  INSERT INTO notifications (user_id, user_nickname, type, message, link)
  VALUES (
    v_user_id,
    v_nickname,
    'achievement',
    '업적 보상으로 연구기록 +' || v_amount || '를 획득했습니다!',
    'my-wallet.html'
  );

  RETURN jsonb_build_object(
    'success',     true,
    'amount',      v_amount,
    'new_balance', v_new_balance
  );

END;
$$;
