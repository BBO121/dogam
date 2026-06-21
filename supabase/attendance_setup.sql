-- ============================================
-- 출석 시스템 DB 설정
-- 작성일: 2026-06-21
-- ============================================

-- 1. 출석 기록 테이블
CREATE TABLE IF NOT EXISTS public.attendance_logs (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attendance_date  date        NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, attendance_date)
);

-- 2. 보너스 수령 기록 테이블 (중복 수령 방지)
CREATE TABLE IF NOT EXISTS public.attendance_rewards (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  month_key    text        NOT NULL,  -- 예: '2026-06'
  reward_step  integer     NOT NULL,  -- 7 / 14 / 21 / 28
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, month_key, reward_step)
);

-- 3. RLS 활성화
ALTER TABLE public.attendance_logs    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_rewards ENABLE ROW LEVEL SECURITY;

-- 4. attendance_logs RLS 정책
CREATE POLICY "attendance_logs: select own"
  ON public.attendance_logs FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT는 RPC로만 처리 (클라이언트 직접 삽입 불가)

-- 5. attendance_rewards RLS 정책
CREATE POLICY "attendance_rewards: select own"
  ON public.attendance_rewards FOR SELECT
  USING (auth.uid() = user_id);

-- ============================================
-- 6. record_attendance RPC
--    출석 기록 + 재화 지급 + 보너스 처리를 원자적으로 수행
-- ============================================
CREATE OR REPLACE FUNCTION record_attendance()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id       uuid    := auth.uid();
  v_today         date    := CURRENT_DATE;
  v_month_key     text    := to_char(CURRENT_DATE, 'YYYY-MM');
  v_count         integer;
  v_research      integer := 5;   -- 기본 보상
  v_keys          integer := 0;
  v_bonus_step    integer := 0;
  v_new_research  integer;
  v_new_keys      integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 출석 기록 삽입 (unique 제약으로 중복 방지, 실패 시 unique_violation 예외)
  INSERT INTO public.attendance_logs (user_id, attendance_date)
  VALUES (v_user_id, v_today);

  -- 이번 달 개인 누적 출석 횟수
  SELECT COUNT(*) INTO v_count
  FROM public.attendance_logs
  WHERE user_id = v_user_id
    AND to_char(attendance_date, 'YYYY-MM') = v_month_key;

  -- 7회 단위 보너스 확인 (7 / 14 / 21 / 28)
  IF v_count IN (7, 14, 21, 28) THEN
    v_bonus_step := v_count;
    -- 보너스 수령 기록 삽입 (이미 받았다면 NOTHING → FOUND = false)
    INSERT INTO public.attendance_rewards (user_id, month_key, reward_step)
    VALUES (v_user_id, v_month_key, v_bonus_step)
    ON CONFLICT (user_id, month_key, reward_step) DO NOTHING;

    IF FOUND THEN
      v_research := v_research + 20;
      v_keys     := v_keys + 1;
    ELSE
      v_bonus_step := 0;  -- 이미 수령한 보너스는 반환 값에서 제외
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
    v_user_id,
    'attendance_reward',
    'attendance',
    'research_records',
    v_research,
    v_new_research,
    CASE WHEN v_bonus_step > 0
      THEN v_bonus_step || '회 달성 보너스 포함'
      ELSE '출석 보상'
    END
  );

  -- 열쇠 로그 (보너스 지급 시에만)
  IF v_keys > 0 THEN
    INSERT INTO public.currency_logs
      (user_id, type, source, currency, amount, balance_after, note)
    VALUES (
      v_user_id,
      'attendance_reward',
      'attendance',
      'keys',
      v_keys,
      v_new_keys,
      v_bonus_step || '회 달성 보너스'
    );
  END IF;

  RETURN json_build_object(
    'success',         true,
    'count',           v_count,
    'research_earned', v_research,
    'keys_earned',     v_keys,
    'bonus_step',      v_bonus_step,
    'new_research',    v_new_research,
    'new_keys',        v_new_keys
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_ATTENDED');
END;
$$;
