-- ============================================
-- 상점 시스템 DB 설정
-- 작성일: 2026-06-21
-- ============================================
-- 설계 메모:
--   is_active(boolean) 대신 status(text)로 설계
--   → active / coming_soon / hidden 3단계로 향후 확장 용이

-- ── 1. shop_items 테이블 ─────────────────────
CREATE TABLE IF NOT EXISTS public.shop_items (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  item_type   text        NOT NULL DEFAULT 'frame',
  -- 1차: frame / 향후: title, profile_deco, event 등
  name        text        NOT NULL,
  description text,
  image_url   text,
  currency    text        NOT NULL CHECK (currency IN ('research_records', 'keys')),
  price       integer     NOT NULL CHECK (price > 0),
  status      text        NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active', 'coming_soon', 'hidden')),
  sort_order  integer     NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ── 2. user_items 테이블 ─────────────────────
CREATE TABLE IF NOT EXISTS public.user_items (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id      uuid        NOT NULL REFERENCES public.shop_items(id) ON DELETE CASCADE,
  purchased_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, item_id)
);

-- ── 3. RLS 활성화 ────────────────────────────
ALTER TABLE public.shop_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_items ENABLE ROW LEVEL SECURITY;

-- ── 4. RLS 정책 ──────────────────────────────

-- shop_items: 로그인 유저면 hidden 제외 모두 조회 가능
DROP POLICY IF EXISTS "shop_items: select" ON public.shop_items;
CREATE POLICY "shop_items: select"
  ON public.shop_items FOR SELECT
  USING (auth.uid() IS NOT NULL AND status != 'hidden');

-- user_items: 본인 구매 목록만 조회
DROP POLICY IF EXISTS "user_items: select own" ON public.user_items;
CREATE POLICY "user_items: select own"
  ON public.user_items FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT/UPDATE/DELETE: RPC(SECURITY DEFINER)로만 처리

-- ── 5. purchase_item RPC ─────────────────────
--    검증 → 차감 → 지급 → 로그 원자적 처리
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

  -- 중복 구매 확인
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

  -- user_items 지급 (unique 제약으로 중복 방지)
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
    'success',     true,
    'item_id',     p_item_id,
    'new_balance', v_new_balance,
    'currency',    v_item.currency
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
END;
$$;

-- ── 6. 실행 권한 ─────────────────────────────
GRANT EXECUTE ON FUNCTION purchase_item(uuid) TO authenticated;

-- ── 7. 인덱스 ────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_shop_items_status    ON public.shop_items (status);
CREATE INDEX IF NOT EXISTS idx_shop_items_item_type ON public.shop_items (item_type);
CREATE INDEX IF NOT EXISTS idx_user_items_user_id   ON public.user_items (user_id);
