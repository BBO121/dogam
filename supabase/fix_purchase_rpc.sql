-- ============================================
-- purchase_item RPC 수정
-- 작성일: 2026-06-25
-- 목적: user_items.quantity 컬럼 없는 기존 테이블에 맞게 RPC 수정
-- ============================================

-- unique / stackable 구분 없이 중복 보유 차단 후 단순 INSERT
-- (quantity 미지원 — 향후 stackable 확장 시 컬럼 추가 + 함수 재작성)
CREATE OR REPLACE FUNCTION purchase_item(p_item_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id     uuid    := auth.uid();
  v_item        record;
  v_balance     integer;
  v_new_balance integer;
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

  -- 중복 보유 차단
  IF EXISTS (
    SELECT 1 FROM public.user_items
    WHERE user_id = v_user_id AND item_id = p_item_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
  END IF;

  -- 재화 잔액 확인 (FOR UPDATE로 동시 구매 방지)
  IF v_item.currency = 'research_records' THEN
    SELECT research_records INTO v_balance
    FROM public.user_wallets WHERE user_id = v_user_id FOR UPDATE;
  ELSE
    SELECT keys INTO v_balance
    FROM public.user_wallets WHERE user_id = v_user_id FOR UPDATE;
  END IF;

  IF v_balance IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  IF v_balance < v_item.price THEN
    RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
  END IF;

  v_new_balance := v_balance - v_item.price;

  -- 재화 차감
  IF v_item.currency = 'research_records' THEN
    UPDATE public.user_wallets
    SET research_records = v_new_balance, updated_at = now()
    WHERE user_id = v_user_id;
  ELSE
    UPDATE public.user_wallets
    SET keys = v_new_balance, updated_at = now()
    WHERE user_id = v_user_id;
  END IF;

  -- user_items 지급
  INSERT INTO public.user_items (user_id, item_id)
  VALUES (v_user_id, p_item_id);

  -- currency_logs 기록
  INSERT INTO public.currency_logs
    (user_id, type, source, currency, amount, balance_after, note)
  VALUES (
    v_user_id,
    'shop_purchase',
    'shop',
    v_item.currency,
    v_item.price,
    v_new_balance,
    v_item.name || ' 구매'
  );

  RETURN json_build_object(
    'success',       true,
    'item_id',       p_item_id,
    'purchase_type', v_item.purchase_type,
    'new_balance',   v_new_balance,
    'currency',      v_item.currency
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
END;
$$;

GRANT EXECUTE ON FUNCTION purchase_item(uuid) TO authenticated;
