-- ============================================
-- shop_items 이중 통화(secondary_currency) 지원 추가
-- 작성일: 2026-06-25
-- ============================================

-- ── 1. 보조 통화 컬럼 추가 ───────────────────
ALTER TABLE public.shop_items
ADD COLUMN IF NOT EXISTS secondary_currency text CHECK (secondary_currency IN ('research_records', 'keys')),
ADD COLUMN IF NOT EXISTS secondary_price    integer CHECK (secondary_price > 0);

-- ── 2. 한정 프레임 보조 통화 설정 ────────────
UPDATE public.shop_items
SET secondary_currency = 'keys',
    secondary_price    = 1
WHERE style_key = 'frame-li-bbo';

-- ── 3. purchase_item RPC — 이중 통화 지원 ────
CREATE OR REPLACE FUNCTION purchase_item(p_item_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id         uuid    := auth.uid();
  v_item            record;
  v_rr_balance      integer;
  v_keys_balance    integer;
  v_balance         integer;
  v_new_balance     integer;
  v_sec_balance     integer;
  v_sec_new_balance integer;
  v_quantity        integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  SELECT * INTO v_item FROM public.shop_items WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  IF v_item.status != 'active' THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_NOT_AVAILABLE');
  END IF;

  IF v_item.sale_end_at IS NOT NULL AND v_item.sale_end_at < now() THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_SALE_ENDED');
  END IF;

  IF v_item.purchase_type = 'unique' THEN
    IF EXISTS (SELECT 1 FROM public.user_items WHERE user_id = v_user_id AND item_id = p_item_id) THEN
      RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
    END IF;
  END IF;

  -- 지갑 잠금 (FOR UPDATE) — 두 통화 동시 조회
  SELECT research_records, keys INTO v_rr_balance, v_keys_balance
  FROM public.user_wallets WHERE user_id = v_user_id FOR UPDATE;

  IF v_rr_balance IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  -- 주 통화 잔액 확인
  v_balance := CASE WHEN v_item.currency = 'research_records' THEN v_rr_balance ELSE v_keys_balance END;
  IF v_balance < v_item.price THEN
    RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
  END IF;
  v_new_balance := v_balance - v_item.price;

  -- 보조 통화 잔액 확인
  IF v_item.secondary_currency IS NOT NULL AND v_item.secondary_price IS NOT NULL THEN
    v_sec_balance := CASE WHEN v_item.secondary_currency = 'research_records' THEN v_rr_balance ELSE v_keys_balance END;
    -- 주 통화와 같을 경우 이미 차감된 잔액 기준으로 재확인
    IF v_item.secondary_currency = v_item.currency THEN
      v_sec_balance := v_new_balance;
    END IF;
    IF v_sec_balance < v_item.secondary_price THEN
      RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
    END IF;
    v_sec_new_balance := v_sec_balance - v_item.secondary_price;
  END IF;

  -- 주 통화 차감
  IF v_item.currency = 'research_records' THEN
    UPDATE public.user_wallets SET research_records = v_new_balance, updated_at = now() WHERE user_id = v_user_id;
  ELSE
    UPDATE public.user_wallets SET keys = v_new_balance, updated_at = now() WHERE user_id = v_user_id;
  END IF;

  -- 보조 통화 차감 (주 통화와 다른 경우만)
  IF v_item.secondary_currency IS NOT NULL AND v_item.secondary_price IS NOT NULL
     AND v_item.secondary_currency != v_item.currency THEN
    IF v_item.secondary_currency = 'research_records' THEN
      UPDATE public.user_wallets SET research_records = v_sec_new_balance, updated_at = now() WHERE user_id = v_user_id;
    ELSE
      UPDATE public.user_wallets SET keys = v_sec_new_balance, updated_at = now() WHERE user_id = v_user_id;
    END IF;
  END IF;

  -- 아이템 지급
  IF v_item.purchase_type = 'unique' THEN
    INSERT INTO public.user_items (user_id, item_id, quantity) VALUES (v_user_id, p_item_id, 1);
    v_quantity := 1;
  ELSE
    INSERT INTO public.user_items (user_id, item_id, quantity)
    VALUES (v_user_id, p_item_id, 1)
    ON CONFLICT (user_id, item_id) DO UPDATE SET quantity = public.user_items.quantity + 1
    RETURNING quantity INTO v_quantity;
  END IF;

  -- 주 통화 로그
  INSERT INTO public.currency_logs (user_id, type, source, currency, amount, balance_after, note)
  VALUES (v_user_id, 'shop_purchase', 'shop', v_item.currency, v_item.price, v_new_balance, v_item.name || ' 구매');

  -- 보조 통화 로그
  IF v_item.secondary_currency IS NOT NULL AND v_item.secondary_price IS NOT NULL THEN
    INSERT INTO public.currency_logs (user_id, type, source, currency, amount, balance_after, note)
    VALUES (v_user_id, 'shop_purchase', 'shop', v_item.secondary_currency, v_item.secondary_price, v_sec_new_balance, v_item.name || ' 구매 (보조)');
  END IF;

  RETURN json_build_object(
    'success',         true,
    'item_id',         p_item_id,
    'purchase_type',   v_item.purchase_type,
    'quantity',        v_quantity,
    'new_balance',     v_new_balance,
    'currency',        v_item.currency,
    'sec_new_balance', v_sec_new_balance,
    'secondary_currency', v_item.secondary_currency
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
END;
$$;

GRANT EXECUTE ON FUNCTION purchase_item(uuid) TO authenticated;
