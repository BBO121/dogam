-- ============================================
-- shop_items 판매 종료일(sale_end_at) 컬럼 추가
-- 작성일: 2026-06-25
-- ============================================

-- ── 1. 컬럼 추가 ─────────────────────────────
ALTER TABLE public.shop_items
ADD COLUMN IF NOT EXISTS sale_end_at timestamptz;

-- ── 2. 한정 아이템 종료일 설정 ────────────────
-- 2026-07-31 23:59:59 KST (= 2026-08-01 00:00:00+09)
UPDATE public.shop_items
SET sale_end_at = '2026-08-01 00:00:00+09'
WHERE style_key = 'frame-li-bbo';

-- ── 3. purchase_item RPC 만료일 체크 추가 ─────
--    기존 RPC에 ITEM_SALE_ENDED 체크만 추가, 나머지 로직은 원본 그대로 유지
CREATE OR REPLACE FUNCTION purchase_item(p_item_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id     uuid    := auth.uid();
  v_item        record;
  v_balance     integer;
  v_new_balance integer;
  v_quantity    integer;
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

  -- ★ 판매 기간 확인 (추가된 부분)
  IF v_item.sale_end_at IS NOT NULL AND v_item.sale_end_at < now() THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_SALE_ENDED');
  END IF;

  -- unique 아이템 중복 구매 차단
  IF v_item.purchase_type = 'unique' THEN
    IF EXISTS (
      SELECT 1 FROM public.user_items
      WHERE user_id = v_user_id AND item_id = p_item_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
    END IF;
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
  IF v_item.purchase_type = 'unique' THEN
    INSERT INTO public.user_items (user_id, item_id, quantity)
    VALUES (v_user_id, p_item_id, 1);

    v_quantity := 1;
  ELSE
    INSERT INTO public.user_items (user_id, item_id, quantity)
    VALUES (v_user_id, p_item_id, 1)
    ON CONFLICT (user_id, item_id) DO UPDATE
    SET quantity = public.user_items.quantity + 1
    RETURNING quantity INTO v_quantity;
  END IF;

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
    'quantity',      v_quantity,
    'new_balance',   v_new_balance,
    'currency',      v_item.currency
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
END;
$$;

GRANT EXECUTE ON FUNCTION purchase_item(uuid) TO authenticated;
