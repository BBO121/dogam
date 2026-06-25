-- ============================================================
-- 긴급 복구: 2026-06-26 (KST) 출석 누락 유저 일괄 처리
-- 대상: 6/25 출석 기록이 있고 6/26 기록이 없는 유저
-- 기본 보상(+5 연구기록) 지급 + 연속 보너스 해당 시 추가 지급
-- ============================================================

DO $$
DECLARE
  r              record;
  v_streak       integer;
  v_cycle_pos    integer;
  v_bonus_res    integer;
  v_already      integer;
  v_new_research integer;
  v_new_keys     integer;
BEGIN
  FOR r IN
    SELECT DISTINCT al.user_id
    FROM public.attendance_logs al
    WHERE al.attendance_date = '2026-06-25'::date
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance_logs al2
        WHERE al2.user_id = al.user_id
          AND al2.attendance_date = '2026-06-26'::date
      )
  LOOP
    -- 1. 6/26 출석 삽입
    INSERT INTO public.attendance_logs (user_id, attendance_date)
    VALUES (r.user_id, '2026-06-26'::date)
    ON CONFLICT (user_id, attendance_date) DO NOTHING;

    -- 2. 지갑 보장
    INSERT INTO public.user_wallets (user_id, research_records, keys)
    VALUES (r.user_id, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;

    -- 3. 6/26 기준 연속 출석일 계산
    WITH ranked AS (
      SELECT attendance_date,
             attendance_date - ROW_NUMBER() OVER (ORDER BY attendance_date)::integer AS grp
      FROM public.attendance_logs
      WHERE user_id = r.user_id
        AND attendance_date <= '2026-06-26'::date
    ),
    today_grp AS (
      SELECT grp FROM ranked WHERE attendance_date = '2026-06-26'::date
    )
    SELECT COUNT(*) INTO v_streak
    FROM ranked rn
    JOIN today_grp g ON rn.grp = g.grp;

    -- 4. 기본 보상 지급 (+5 연구기록)
    UPDATE public.user_wallets
    SET research_records = research_records + 5,
        updated_at       = now()
    WHERE user_id = r.user_id
    RETURNING research_records, keys INTO v_new_research, v_new_keys;

    INSERT INTO public.currency_logs
      (user_id, type, source, currency, amount, balance_after, note)
    VALUES (r.user_id, 'attendance_reward', 'attendance',
            'research_records', 5, v_new_research, '6/26 출석 복구 지급');

    -- 5. 연속 보너스 해당 여부 확인
    IF v_streak % 7 = 0 THEN
      SELECT COUNT(*) INTO v_already
      FROM public.attendance_rewards
      WHERE user_id = r.user_id AND achieved_date = '2026-06-26'::date;

      IF v_already = 0 THEN
        v_cycle_pos := v_streak % 28;
        v_bonus_res := CASE v_cycle_pos
          WHEN 7  THEN 20
          WHEN 14 THEN 25
          WHEN 21 THEN 30
          WHEN 0  THEN 40
          ELSE 0
        END;

        INSERT INTO public.attendance_rewards
          (user_id, month_key, reward_step, achieved_date)
        VALUES (r.user_id, '2026-06', v_streak, '2026-06-26'::date)
        ON CONFLICT DO NOTHING;

        UPDATE public.user_wallets
        SET research_records = research_records + v_bonus_res,
            keys             = keys + 1,
            updated_at       = now()
        WHERE user_id = r.user_id
        RETURNING research_records, keys INTO v_new_research, v_new_keys;

        INSERT INTO public.currency_logs
          (user_id, type, source, currency, amount, balance_after, note)
        VALUES (r.user_id, 'attendance_reward', 'attendance',
                'research_records', v_bonus_res, v_new_research,
                '6/26 출석 복구 - ' || v_streak || '일 연속 보너스');

        INSERT INTO public.currency_logs
          (user_id, type, source, currency, amount, balance_after, note)
        VALUES (r.user_id, 'attendance_reward', 'attendance',
                'keys', 1, v_new_keys,
                '6/26 출석 복구 - ' || v_streak || '일 연속 보너스');

        RAISE NOTICE '유저 % — 연속 %일 보너스 지급 (+%연구기록, +1열쇠)',
          r.user_id, v_streak, v_bonus_res;
      END IF;
    END IF;

    RAISE NOTICE '유저 % — 6/26 출석 복구 완료 (연속 %일)', r.user_id, v_streak;
  END LOOP;
END $$;
