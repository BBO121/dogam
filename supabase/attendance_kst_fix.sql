-- ============================================================
-- 긴급 수정: record_attendance() KST 기준으로 재정의
-- v_today를 BEGIN 블록에서 명시적으로 KST 변환하여 할당
-- ============================================================

CREATE OR REPLACE FUNCTION record_attendance()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id      uuid;
  v_today        date;
  v_streak       integer;
  v_research     integer := 5;
  v_keys         integer := 0;
  v_bonus        boolean := false;
  v_new_research integer;
  v_new_keys     integer;
  v_already      integer;
  v_cycle_pos    integer;
BEGIN
  v_user_id := auth.uid();
  -- KST 기준 오늘 날짜 (UTC+9)
  v_today   := (now() AT TIME ZONE 'Asia/Seoul')::date;

  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- user_wallets row 보장
  INSERT INTO public.user_wallets (user_id, research_records, keys)
  VALUES (v_user_id, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- 출석 기록 삽입 (당일 중복 방지)
  INSERT INTO public.attendance_logs (user_id, attendance_date)
  VALUES (v_user_id, v_today);

  -- 연속 출석일 계산 (오늘 포함)
  WITH ranked AS (
    SELECT attendance_date,
           attendance_date - ROW_NUMBER() OVER (ORDER BY attendance_date)::integer AS grp
    FROM public.attendance_logs
    WHERE user_id = v_user_id
      AND attendance_date <= v_today
  ),
  today_grp AS (
    SELECT grp FROM ranked WHERE attendance_date = v_today
  )
  SELECT COUNT(*) INTO v_streak
  FROM ranked r
  JOIN today_grp g ON r.grp = g.grp;

  -- 7일 배수마다 보너스 (28일 주기: 7→+20, 14→+25, 21→+30, 28(0)→+40)
  IF v_streak % 7 = 0 THEN
    SELECT COUNT(*) INTO v_already
    FROM public.attendance_rewards
    WHERE user_id = v_user_id AND achieved_date = v_today;

    IF v_already = 0 THEN
      INSERT INTO public.attendance_rewards
        (user_id, month_key, reward_step, achieved_date)
      VALUES
        (v_user_id,
         to_char(v_today, 'YYYY-MM'),
         v_streak,
         v_today);

      v_cycle_pos := v_streak % 28;
      v_research  := v_research + CASE v_cycle_pos
        WHEN 7  THEN 20
        WHEN 14 THEN 25
        WHEN 21 THEN 30
        WHEN 0  THEN 40
      END;
      v_keys  := v_keys + 1;
      v_bonus := true;
    END IF;
  END IF;

  -- 지갑 업데이트
  UPDATE public.user_wallets
  SET research_records = research_records + v_research,
      keys             = keys + v_keys,
      updated_at       = now()
  WHERE user_id = v_user_id
  RETURNING research_records, keys INTO v_new_research, v_new_keys;

  -- 연구기록 로그
  INSERT INTO public.currency_logs
    (user_id, type, source, currency, amount, balance_after, note)
  VALUES (
    v_user_id, 'attendance_reward', 'attendance',
    'research_records', v_research, v_new_research,
    CASE WHEN v_bonus THEN v_streak || '일 연속 출석 보너스 포함' ELSE '출석 보상' END
  );

  IF v_keys > 0 THEN
    INSERT INTO public.currency_logs
      (user_id, type, source, currency, amount, balance_after, note)
    VALUES (
      v_user_id, 'attendance_reward', 'attendance',
      'keys', v_keys, v_new_keys,
      v_streak || '일 연속 출석 보너스'
    );
  END IF;

  RETURN json_build_object(
    'success',         true,
    'streak',          v_streak,
    'research_earned', v_research,
    'keys_earned',     v_keys,
    'bonus',           v_bonus,
    'new_research',    v_new_research,
    'new_keys',        v_new_keys
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_ATTENDED');
END;
$$;

GRANT EXECUTE ON FUNCTION record_attendance() TO authenticated;
