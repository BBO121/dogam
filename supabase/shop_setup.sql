-- ============================================
-- 상점 시스템 DB 설정
-- 작성일: 2026-06-21
-- 수정일: 2026-06-21 (purchase_type / quantity 확장성 추가)
-- ============================================

-- ── 1. shop_items 테이블 ─────────────────────
CREATE TABLE IF NOT EXISTS public.shop_items (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  item_type      text        NOT NULL DEFAULT 'frame',
  -- 1차: frame / 향후: title, profile_deco, event 등
  name           text        NOT NULL,
  description    text,
  image_url      text,
  currency       text        NOT NULL CHECK (currency IN ('research_records', 'keys')),
  price          integer     NOT NULL CHECK (price > 0),
  status         text        NOT NULL DEFAULT 'active'
                             CHECK (status IN ('active', 'coming_soon', 'hidden')),
  purchase_type  text        NOT NULL DEFAULT 'unique'
                             CHECK (purchase_type IN ('unique', 'stackable')),
  -- unique    : 1인 1개 (프레임·칭호 등 영구 소장형)
  -- stackable : 중복 구매 가능 (소모품·열쇠 꾸러미·이름 변경권 등)
  sort_order     integer     NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- ── 2. user_items 테이블 ─────────────────────
CREATE TABLE IF NOT EXISTS public.user_items (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id      uuid        NOT NULL REFERENCES public.shop_items(id) ON DELETE CASCADE,
  quantity     integer     NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  -- unique 아이템: 항상 1
  -- stackable 아이템: 구매할 때마다 +1
  purchased_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, item_id)
);

-- ── 3. RLS 활성화 ────────────────────────────
ALTER TABLE public.shop_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_items ENABLE ROW LEVEL SECURITY;

-- ── 4. RLS 정책 ──────────────────────────────
DROP POLICY IF EXISTS "shop_items: select" ON public.shop_items;
CREATE POLICY "shop_items: select"
  ON public.shop_items FOR SELECT
  USING (auth.uid() IS NOT NULL AND status != 'hidden');

DROP POLICY IF EXISTS "user_items: select own" ON public.user_items;
CREATE POLICY "user_items: select own"
  ON public.user_items FOR SELECT
  USING (auth.uid() = user_id);

-- ── 5. purchase_item RPC ─────────────────────
--    unique    → 중복 구매 차단
--    stackable → ON CONFLICT DO UPDATE (quantity +1)
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
  --   unique    : 단순 INSERT (unique 제약으로 중복 방지됨)
  --   stackable : ON CONFLICT → quantity +1
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

-- ── 6. 실행 권한 ─────────────────────────────
GRANT EXECUTE ON FUNCTION purchase_item(uuid) TO authenticated;

-- ── 7. 인덱스 ────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_shop_items_status        ON public.shop_items (status);
CREATE INDEX IF NOT EXISTS idx_shop_items_item_type     ON public.shop_items (item_type);
CREATE INDEX IF NOT EXISTS idx_shop_items_purchase_type ON public.shop_items (purchase_type);
CREATE INDEX IF NOT EXISTS idx_user_items_user_id       ON public.user_items (user_id);
