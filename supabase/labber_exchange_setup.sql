-- ════════════════════════════════════════════════
-- 수상한 연구실 — 열쇠 → 연구기록 교환 RPC
-- 교환비: 열쇠 1개 = 연구기록 25개
-- ════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.exchange_keys_for_research_records(
  p_quantity integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      uuid    := auth.uid();
  v_rate         integer := 25;

  v_keys_balance integer;
  v_rr_balance   integer;

  v_new_keys     integer;
  v_new_rr       integer;
  v_gain         integer;
BEGIN

  -- 로그인 확인
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'NOT_AUTHENTICATED'
    );
  END IF;


  -- 교환 수량 검증
  IF p_quantity IS NULL OR p_quantity < 1 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INVALID_QUANTITY'
    );
  END IF;


  -- 지갑 행 잠금
  SELECT
    keys,
    research_records
  INTO
    v_keys_balance,
    v_rr_balance
  FROM public.user_wallets
  WHERE user_id = v_user_id
  FOR UPDATE;


  -- 지갑 없음
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'WALLET_NOT_FOUND'
    );
  END IF;


  -- 혹시 기존 데이터에 NULL이 존재할 경우 방어
  v_keys_balance := COALESCE(v_keys_balance, 0);
  v_rr_balance   := COALESCE(v_rr_balance, 0);


  -- 보유 열쇠 확인
  IF v_keys_balance < p_quantity THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INSUFFICIENT_KEYS'
    );
  END IF;


  -- 서버 고정 교환비
  v_gain     := p_quantity * v_rate;
  v_new_keys := v_keys_balance - p_quantity;
  v_new_rr   := v_rr_balance + v_gain;


  -- 열쇠 차감 + 연구기록 지급
  UPDATE public.user_wallets
  SET
    keys             = v_new_keys,
    research_records = v_new_rr,
    updated_at       = now()
  WHERE user_id = v_user_id;


  -- 열쇠 소비 로그
  INSERT INTO public.currency_logs
    (
      user_id,
      type,
      source,
      currency,
      amount,
      balance_after,
      note
    )
  VALUES
    (
      v_user_id,
      'labber_exchange',
      'suspicious_lab_exchange',
      'keys',
      p_quantity,
      v_new_keys,
      '열쇠 ' || p_quantity || '개 교환'
    );


  -- 연구기록 지급 로그
  INSERT INTO public.currency_logs
    (
      user_id,
      type,
      source,
      currency,
      amount,
      balance_after,
      note
    )
  VALUES
    (
      v_user_id,
      'labber_exchange',
      'suspicious_lab_exchange',
      'research_records',
      v_gain,
      v_new_rr,
      '열쇠 ' || p_quantity || '개 교환'
    );


  RETURN jsonb_build_object(
    'success', true,
    'new_keys', v_new_keys,
    'new_research', v_new_rr,
    'gained', v_gain
  );

END;
$$;


-- SECURITY DEFINER 재화 RPC 권한 제한
REVOKE ALL
ON FUNCTION public.exchange_keys_for_research_records(integer)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.exchange_keys_for_research_records(integer)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.exchange_keys_for_research_records(integer)
TO authenticated;