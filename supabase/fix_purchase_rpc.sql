-- ============================================
-- purchase_item RPC 최종 수정
-- 작성일: 2026-06-25
-- 수정일: 2026-06-25
-- 변경:
--   - quantity 제거 (user_items에 컬럼 없음)
--   - purchase_type 제거 (shop_items에 컬럼 없음)
--   - 이중 통화 차감 지원 (secondary_currency / secondary_price)
--   - currency_logs 두 통화 각각 기록
-- ============================================

CREATE OR REPLACE FUNCTION purchase_item(p_item_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id         uuid    := auth.uid();
  v_item            record;
  v_rr_balance      integer;
  v_keys_balance    integer;
  v_new_balance     integer;
  v_sec_balance     integer;
  v_sec_new_balance integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 상품 조회
  SELECT * INTO v_item FROM public.shop_items WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  -- 판매 상태 확인
  IF v_item.status != 'active' THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_NOT_AVAILABLE');
  END IF;

  -- 판매 기간 확인
  IF v_item.sale_end_at IS NOT NULL AND v_item.sale_end_at < now() THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_SALE_ENDED');
  END IF;

  -- 중복 보유 차단
  IF EXISTS (
    SELECT 1 FROM public.user_items
    WHERE user_id = v_user_id AND item_id = p_item_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
  END IF;

  -- 지갑 잠금 (FOR UPDATE) — 두 통화 동시 조회
  SELECT research_records, keys
  INTO v_rr_balance, v_keys_balance
  FROM public.user_wallets
  WHERE user_id = v_user_id FOR UPDATE;

  IF v_rr_balance IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  -- 주 통화 잔액 확인
  IF v_item.currency = 'research_records' THEN
    IF v_rr_balance < v_item.price THEN
      RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
    END IF;
    v_new_balance := v_rr_balance - v_item.price;
  ELSE
    IF v_keys_balance < v_item.price THEN
      RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
    END IF;
    v_new_balance := v_keys_balance - v_item.price;
  END IF;

  -- 보조 통화 잔액 확인
  IF v_item.secondary_currency IS NOT NULL AND v_item.secondary_price IS NOT NULL THEN
    IF v_item.secondary_currency = v_item.currency THEN
      -- 주 통화와 동일: 이미 차감된 잔액 기준
      v_sec_balance := v_new_balance;
    ELSIF v_item.secondary_currency = 'research_records' THEN
      v_sec_balance := v_rr_balance;
    ELSE
      v_sec_balance := v_keys_balance;
    END IF;

    IF v_sec_balance < v_item.secondary_price THEN
      RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
    END IF;
    v_sec_new_balance := v_sec_balance - v_item.secondary_price;
  END IF;

  -- 주 통화 차감
  IF v_item.currency = 'research_records' THEN
    UPDATE public.user_wallets
    SET research_records = v_new_balance, updated_at = now()
    WHERE user_id = v_user_id;
  ELSE
    UPDATE public.user_wallets
    SET keys = v_new_balance, updated_at = now()
    WHERE user_id = v_user_id;
  END IF;

  -- 보조 통화 차감 (주 통화와 다른 경우만)
  IF v_item.secondary_currency IS NOT NULL AND v_item.secondary_price IS NOT NULL
     AND v_item.secondary_currency != v_item.currency THEN
    IF v_item.secondary_currency = 'research_records' THEN
      UPDATE public.user_wallets
      SET research_records = v_sec_new_balance, updated_at = now()
      WHERE user_id = v_user_id;
    ELSE
      UPDATE public.user_wallets
      SET keys = v_sec_new_balance, updated_at = now()
      WHERE user_id = v_user_id;
    END IF;
  END IF;

  -- user_items 지급
  INSERT INTO public.user_items (user_id, item_id)
  VALUES (v_user_id, p_item_id);

  -- 주 통화 로그
  INSERT INTO public.currency_logs
    (user_id, type, source, currency, amount, balance_after, note)
  VALUES (
    v_user_id, 'shop_purchase', 'shop',
    v_item.currency, v_item.price, v_new_balance,
    v_item.name || ' 구매'
  );

  -- 보조 통화 로그
  IF v_item.secondary_currency IS NOT NULL AND v_item.secondary_price IS NOT NULL THEN
    INSERT INTO public.currency_logs
      (user_id, type, source, currency, amount, balance_after, note)
    VALUES (
      v_user_id, 'shop_purchase', 'shop',
      v_item.secondary_currency, v_item.secondary_price, v_sec_new_balance,
      v_item.name || ' 구매 (보조)'
    );
  END IF;

  RETURN json_build_object(
    'success',            true,
    'item_id',            p_item_id,
    'new_balance',        v_new_balance,
    'currency',           v_item.currency,
    'sec_new_balance',    v_sec_new_balance,
    'secondary_currency', v_item.secondary_currency
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
END;
$$;

GRANT EXECUTE ON FUNCTION purchase_item(uuid) TO authenticated;
