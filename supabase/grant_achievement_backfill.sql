-- ============================================================
-- grant_achievement_backfill
-- 기존 업적 보유 유저 1회 필백: 연구기록 지급 + currency_logs + notifications
-- 호출: sb.rpc('grant_achievement_backfill', { p_user_id: userId })
-- 중복 실행 안전: currency_logs에 achievement_backfill 기록이 있으면 스킵
-- ============================================================

CREATE OR REPLACE FUNCTION public.grant_achievement_backfill(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role text;
  v_nickname    text;
  v_total       integer := 0;
  v_new_balance integer;
  rec           RECORD;
BEGIN

  -- 관리자 / 스태프 권한 확인
  SELECT raw_user_meta_data->>'role'
  INTO   v_caller_role
  FROM   auth.users
  WHERE  id = auth.uid();

  IF v_caller_role NOT IN ('admin', 'staff') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'NOT_AUTHORIZED'
    );
  END IF;

  -- 중복 실행 방지 (idempotent)
  IF EXISTS (
    SELECT 1
    FROM currency_logs
    WHERE user_id = p_user_id
      AND type    = 'achievement_backfill'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'ALREADY_DONE'
    );
  END IF;

  -- 유저의 전체 업적 합산
  FOR rec IN
    SELECT a.is_hidden
    FROM   user_achievements ua
    JOIN   achievements a ON a.code = ua.achievement_code
    WHERE  ua.user_id = p_user_id
  LOOP
    v_total := v_total + CASE WHEN rec.is_hidden THEN 10 ELSE 5 END;
  END LOOP;

  -- 업적 없는 유저는 스킵
  IF v_total = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'amount',  0,
      'skipped', true
    );
  END IF;

  -- 닉네임 조회 (알림용)
  SELECT COALESCE(
    raw_user_meta_data->>'display_name',
    raw_user_meta_data->>'nickname'
  )
  INTO  v_nickname
  FROM  auth.users
  WHERE id = p_user_id;

  -- 지갑 업데이트
  UPDATE user_wallets
  SET    research_records = research_records + v_total,
         updated_at       = now()
  WHERE  user_id = p_user_id
  RETURNING research_records INTO v_new_balance;

  -- 거래 로그 기록 (유저당 1건)
  INSERT INTO currency_logs (user_id, type, currency, amount, balance_after, note)
  VALUES (
    p_user_id,
    'achievement_backfill',
    'research_records',
    v_total,
    v_new_balance,
    '업적 보상 필백'
  );

  -- 알림 생성 (유저당 1개)
  IF v_nickname IS NOT NULL THEN
    INSERT INTO notifications (user_nickname, type, message, link)
    VALUES (
      v_nickname,
      'achievement',
      '기존 업적 보상으로 연구기록 +' || v_total || '을 획득했습니다!',
      'my-wallet.html'
    );
  END IF;

  RETURN jsonb_build_object(
    'success',     true,
    'amount',      v_total,
    'new_balance', v_new_balance
  );

END;
$$;
