-- ============================================================
-- 출석 시스템: 월간 누적 → 7일 연속 출석 보너스로 전환
-- 기존 attendance_logs / attendance_rewards 데이터는 유지
-- ============================================================

-- 1. achieved_date 컬럼 추가 (nullable, 기존 행은 null로 보존)
ALTER TABLE public.attendance_rewards
  ADD COLUMN IF NOT EXISTS achieved_date date;

-- 2. 기존 (user_id, month_key, reward_step) unique 제약 제거
--    같은 달에 연속 출석이 끊겼다가 다시 7일 달성하면 reward_step이 동일해서 중복 차단됨
--    제약 이름이 환경마다 다를 수 있으므로 pg_constraint 조회 후 동적 삭제
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE t.relname = 'attendance_rewards'
      AND n.nspname  = 'public'
      AND c.contype  = 'u'
      AND EXISTS (
        SELECT 1 FROM pg_attribute a
        WHERE a.attrelid = c.conrelid
          AND a.attnum   = ANY(c.conkey)
          AND a.attname  = 'month_key'
      )
  LOOP
    EXECUTE format('ALTER TABLE public.attendance_rewards DROP CONSTRAINT %I', r.conname);
    RAISE NOTICE '제거된 unique 제약: %', r.conname;
  END LOOP;
END $$;

-- 3. 새로운 중복 방지 partial unique index (achieved_date 기반)
--    신규 행(achieved_date IS NOT NULL)만 대상으로 하루 1회 보너스 보장
CREATE UNIQUE INDEX IF NOT EXISTS attendance_rewards_user_achieved_date_key
  ON public.attendance_rewards (user_id, achieved_date)
  WHERE achieved_date IS NOT NULL;

-- 4. 연속 출석 기반 record_attendance() 함수 교체
--    보너스: 연속 7일마다 연구기록 +20, 열쇠 +1 (무한 반복)
CREATE OR REPLACE FUNCTION record_attendance()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id      uuid    := auth.uid();
  v_today        date    := timezone('Asia/Seoul', now())::date;
  v_streak       integer;
  v_research     integer := 5;
  v_keys         integer := 0;
  v_bonus        boolean := false;
  v_new_research integer;
  v_new_keys     integer;
  v_already      integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- user_wallets row 보장 (가입 트리거 누락 유저 대비)
  INSERT INTO public.user_wallets (user_id, research_records, keys)
  VALUES (v_user_id, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- 출석 기록 삽입 (unique 제약으로 당일 중복 방지)
  INSERT INTO public.attendance_logs (user_id, attendance_date)
  VALUES (v_user_id, v_today);

  -- 연속 출석일 계산 (오늘 포함)
  -- 날짜 - row_number 가 같은 그룹 = 연속된 날짜
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

  -- 7일 배수마다 보너스 (무한 반복)
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

      v_research := v_research + 20;
      v_keys     := v_keys + 1;
      v_bonus    := true;
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

  -- 열쇠 로그 (보너스 지급 시에만)
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
