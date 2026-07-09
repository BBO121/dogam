-- ============================================
-- 범프 티켓 시스템 DB 설정
-- 작성일: 2026-07-05
--
-- 포함 내용:
--   0. shop_items CHECK 제약 방어적 확인/재생성 (item_type / purchase_type)
--   1. shop_items 확장 (item_key, grant_qty) + 범프 티켓 3종 등록
--   2. user_items 확장 (quantity, item_key) + 소모품 잔고용 부분 유니크 인덱스
--   3. purchase_item RPC 갱신 — unique 분기는 기존과 100% 동일, stackable 분기만 추가
--                                + hidden 상품은 admin/staff만 구매 테스트 가능하도록 예외 추가
--   4. item_use_logs 테이블 (아이템 사용 이력)
--   5. use_bump_ticket RPC — 조건 확인 → 티켓 차감(0개 되면 row 삭제) → adoptions.created_at 갱신 →
--                            로그 기록 → 알림 생성을 한 트랜잭션으로 처리
--   6. 인덱스

--   7. shop_items SELECT 정책 — admin/staff는 status='hidden' 상품도 조회 가능
--                                (실사용자에게는 계속 숨김, 개발자만 미리보기)
--
-- 가격/할인 확정 (2026-07-09): 1장 30 / 5장 135(10% 할인) / 10장 255(15% 할인)
-- ============================================


-- ─────────────────────────────────────────────
-- 0. CHECK 제약 방어적 확인/재생성
--    (fix_purchase_rpc.sql 주석상 운영 DB에서 purchase_type 컬럼이
--     대시보드로 드롭됐을 가능성이 있어, 추적된 SQL만으로는
--     현재 제약 상태를 100% 신뢰할 수 없음 → 방어적으로 재보정)
-- ─────────────────────────────────────────────

-- purchase_type 컬럼이 없을 수 있으므로 방어적으로 재추가 (이미 있으면 무시)
ALTER TABLE public.shop_items
  ADD COLUMN IF NOT EXISTS purchase_type text NOT NULL DEFAULT 'unique';

-- 기존 CHECK 제약을 이름 무관하게 찾아서 제거 후 'stackable' 포함하도록 재생성
DO $$
DECLARE con_name text;
BEGIN
  SELECT conname INTO con_name
  FROM pg_constraint
  WHERE conrelid = 'public.shop_items'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%purchase_type%';
  IF con_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.shop_items DROP CONSTRAINT ' || quote_ident(con_name);
  END IF;
END $$;

ALTER TABLE public.shop_items
  ADD CONSTRAINT shop_items_purchase_type_check
  CHECK (purchase_type IN ('unique', 'stackable'));

-- item_type은 원래 CHECK가 없지만, 이후 추가됐을 가능성을 대비해 동일하게 확인
-- (있다면 제거만 하고 재생성하지 않음 — item_type은 자유 text로 유지, 'consumable' 값 허용)
DO $$
DECLARE con_name text;
BEGIN
  SELECT conname INTO con_name
  FROM pg_constraint
  WHERE conrelid = 'public.shop_items'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%item_type%';
  IF con_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.shop_items DROP CONSTRAINT ' || quote_ident(con_name);
  END IF;
END $$;


-- ─────────────────────────────────────────────
-- 1. shop_items 확장 + 범프 티켓 상품 등록
-- ─────────────────────────────────────────────

ALTER TABLE public.shop_items
  ADD COLUMN IF NOT EXISTS item_key      text,
  ADD COLUMN IF NOT EXISTS grant_qty     integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS discount_note text;
  -- discount_note: 썸네일에 표시하는 할인 배지 문구 (예: "2장 할인"). 없으면 NULL.

-- 같은 item_key(ticket-bump) 안에서 SKU(1/5/10장)를 구분하는 자연키.
-- 재실행 시 중복 생성 없이 UPSERT되도록 하는 충돌 대상.
CREATE UNIQUE INDEX IF NOT EXISTS unique_shop_items_ticket_sku
  ON public.shop_items (item_key, grant_qty)
  WHERE item_key IS NOT NULL;

-- 가격/할인 확정값 (2026-07-09):
--   1장  : price 30  (할인 없음)
--   5장  : price 135 (정가 150, 10% 할인)
--   10장 : price 255 (정가 300, 15% 할인)
-- status='hidden': 실사이트 일반 사용자에게는 노출 금지, admin/staff만 RLS 예외로 미리보기.
--       정식 오픈 시 아래처럼 UPDATE로 active 전환:
--         UPDATE public.shop_items SET status = 'active' WHERE item_key = 'ticket-bump';
-- 재실행 방지: item_key+grant_qty 기준으로 이미 있으면 내용만 갱신(UPSERT), 새로 만들지 않음.
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, original_price,
   status, image_url, item_key, grant_qty, purchase_type, sub_category, credit, discount_note, sort_order)
VALUES
(
  'consumable', '분양 끌올 티켓 1장', '내 분양글을 분양 목록 최상단으로 끌어올려요.',
  'research_records', 30, NULL,
  'hidden', '../images/shop/ticket_bump_1.png',
  'ticket-bump', 1, 'stackable', '티켓', '사월', NULL, 10
),
(
  'consumable', '분양 끌올 티켓 5장 묶음', '내 분양글을 분양 목록 최상단으로 끌어올려요.',
  'research_records', 135, 150,
  'hidden', '../images/shop/ticket_bump_2.png',
  'ticket-bump', 5, 'stackable', '티켓', '사월', '10% 할인', 20
),
(
  'consumable', '분양 끌올 티켓 10장 묶음', '내 분양글을 분양 목록 최상단으로 끌어올려요.',
  'research_records', 255, 300,
  'hidden', '../images/shop/ticket_bump_3.png',
  'ticket-bump', 10, 'stackable', '티켓', '사월', '15% 할인', 30
)
ON CONFLICT (item_key, grant_qty) WHERE item_key IS NOT NULL
DO UPDATE SET
  item_type      = EXCLUDED.item_type,
  name           = EXCLUDED.name,
  description    = EXCLUDED.description,
  currency       = EXCLUDED.currency,
  image_url      = EXCLUDED.image_url,
  purchase_type  = EXCLUDED.purchase_type,
  sub_category   = EXCLUDED.sub_category,
  credit         = EXCLUDED.credit,
  sort_order     = EXCLUDED.sort_order;
  -- price/original_price/discount_note/status는 UPSERT 대상에서 제외 — 이미 확정/전환해둔 값을
  -- 재실행 시(예: 오타 수정 등으로 이 스크립트를 다시 돌릴 때) 되돌리지 않기 위함.
  -- 특히 status 제외가 중요: 정식 오픈 때 'active'로 UPDATE해둔 뒤 이 스크립트를 재실행해도
  -- 'hidden'으로 되돌아가지 않음.


-- ─────────────────────────────────────────────
-- 2. user_items 확장 (quantity 재도입 + item_key 합산 키)
-- ─────────────────────────────────────────────

ALTER TABLE public.user_items
  ADD COLUMN IF NOT EXISTS quantity  integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS item_key  text;

-- 같은 item_key를 가진 여러 SKU(1/5/10장) 구매를 하나의 잔고 row로 합산하기 위한 키
-- 기존 UNIQUE(user_id, item_id)는 그대로 유지 → unique 아이템(프레임/스티커) 동작 불변
CREATE UNIQUE INDEX IF NOT EXISTS unique_user_items_item_key
  ON public.user_items (user_id, item_key)
  WHERE item_key IS NOT NULL;


-- ─────────────────────────────────────────────
-- 3. purchase_item RPC 갱신
--    - purchase_type = 'unique'  : 기존 로직과 100% 동일
--    - purchase_type = 'stackable': item_key 기준으로 quantity 합산, 반복 구매 허용
--    - status = 'hidden' 상품: admin/staff만 예외적으로 구매 가능 (일반 유저는 계속 차단)
-- ─────────────────────────────────────────────

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
  v_quantity        integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 상품 조회
  SELECT * INTO v_item FROM public.shop_items WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  -- 판매 상태 확인 — hidden 상품은 admin/staff만 예외적으로 구매 가능
  --                  (실사이트 오픈 전 구매 테스트용. shop_items SELECT 정책과 동일한 역할 판별)
  IF v_item.status != 'active' THEN
    IF NOT (
      v_item.status = 'hidden'
      AND ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text) IN ('admin', 'staff')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'ITEM_NOT_AVAILABLE');
    END IF;
  END IF;

  -- 판매 기간 확인
  IF v_item.sale_end_at IS NOT NULL AND v_item.sale_end_at < now() THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_SALE_ENDED');
  END IF;

  -- 중복 보유 차단: unique 아이템에만 적용 (stackable은 반복 구매 허용)
  IF v_item.purchase_type = 'unique' THEN
    IF EXISTS (
      SELECT 1 FROM public.user_items
      WHERE user_id = v_user_id AND item_id = p_item_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'ALREADY_OWNED');
    END IF;
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

  -- 아이템 지급
  IF v_item.purchase_type = 'unique' THEN
    -- 기존과 동일: 1인 1개, quantity는 컬럼 기본값(1) 사용
    INSERT INTO public.user_items (user_id, item_id)
    VALUES (v_user_id, p_item_id);
    v_quantity := 1;
  ELSE
    -- stackable: item_key 기준으로 여러 SKU 구매를 하나의 잔고로 합산
    INSERT INTO public.user_items (user_id, item_id, item_key, quantity)
    VALUES (v_user_id, p_item_id, v_item.item_key, v_item.grant_qty)
    ON CONFLICT (user_id, item_key) WHERE item_key IS NOT NULL
    DO UPDATE SET quantity     = public.user_items.quantity + v_item.grant_qty,
                  purchased_at = now()
    RETURNING quantity INTO v_quantity;
  END IF;

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
    'purchase_type',      v_item.purchase_type,
    'quantity',           v_quantity,
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


-- ─────────────────────────────────────────────
-- 4. item_use_logs 테이블 (아이템 사용 이력)
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.item_use_logs (
  id          bigint      GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_key    text        NOT NULL,
  target_type text        NOT NULL,
  -- 이번 기능에서는 target_type = 'adoption' 만 사용.
  -- adoptions 참조 FK — 향후 target_type이 늘어나면 폴리모픽 구조로 재설계 필요.
  target_id   bigint      REFERENCES public.adoptions(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  metadata    jsonb
);

ALTER TABLE public.item_use_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "item_use_logs: select own" ON public.item_use_logs;
CREATE POLICY "item_use_logs: select own"
  ON public.item_use_logs FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT는 SECURITY DEFINER RPC(use_bump_ticket)에서만 수행 — 별도 INSERT 정책 없음

CREATE INDEX IF NOT EXISTS idx_item_use_logs_user_created
  ON public.item_use_logs (user_id, created_at DESC);


-- ─────────────────────────────────────────────
-- 5. use_bump_ticket RPC
--    조건 확인(본인 소유/진행중 상태/앞선 최신글 20개 이상) → 티켓 차감
--    → adoptions.created_at 갱신 → 로그 기록 → 알림 생성을 원자 처리
--    실패 시(중간의 어떤 체크라도 걸리면) 티켓 차감 없이 그대로 반환
-- ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.use_bump_ticket(p_adoption_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id         uuid := auth.uid();
  v_adoption        record;
  v_ticket_qty      integer;
  v_ahead_count     integer;
  v_new_qty         integer;
  v_new_created_at  timestamptz;
  v_link            text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 대상 분양글 잠금 + 조회
  SELECT * INTO v_adoption
    FROM adoptions
   WHERE id = p_adoption_id
   FOR UPDATE;

  IF v_adoption IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF v_adoption.user_id IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER');
  END IF;

  IF v_adoption.status IS DISTINCT FROM '분양중' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADOPTION_CLOSED');
  END IF;

  -- 티켓 잔고 잠금 + 조회
  SELECT quantity INTO v_ticket_qty
    FROM user_items
   WHERE user_id = v_user_id AND item_key = 'ticket-bump'
   FOR UPDATE;

  IF v_ticket_qty IS NULL OR v_ticket_qty < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_TICKET');
  END IF;

  -- 사용 조건: 내 분양글보다 created_at이 더 최신인 분양글이 20개 이상
  -- (상태/타입 무관 — 분양 목록 페이지의 필터 없는 전체 정렬 기준과 동일)
  SELECT count(*) INTO v_ahead_count
    FROM adoptions
   WHERE created_at > v_adoption.created_at;

  IF v_ahead_count < 20 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ENOUGH_AHEAD');
  END IF;

  -- 여기서부터 실제 처리 (차감/갱신/로그/알림)
  -- 차감 후 0개가 되면 row 자체를 삭제 (0개 상태로 가방에 남지 않도록)
  IF v_ticket_qty = 1 THEN
    DELETE FROM user_items
     WHERE user_id = v_user_id AND item_key = 'ticket-bump';
    v_new_qty := 0;
  ELSE
    UPDATE user_items
       SET quantity = quantity - 1
     WHERE user_id = v_user_id AND item_key = 'ticket-bump'
     RETURNING quantity INTO v_new_qty;
  END IF;

  UPDATE adoptions
     SET created_at = now()
   WHERE id = p_adoption_id
   RETURNING created_at INTO v_new_created_at;

  v_link := 'adoption-detail.html?id=' || p_adoption_id;

  INSERT INTO item_use_logs (user_id, item_key, target_type, target_id, metadata)
  VALUES (
    v_user_id, 'ticket-bump', 'adoption', p_adoption_id,
    jsonb_build_object('character_name', v_adoption.character_name)
  );

  PERFORM notify_user_by_id(
    v_user_id,
    'ticket_bump_used',
    '내 분양글 "' || coalesce(v_adoption.character_name, '') || '"이(가) 분양 끌올 티켓으로 끌어올려졌어요.',
    v_link
  );

  RETURN jsonb_build_object(
    'success',     true,
    'new_quantity', v_new_qty,
    'created_at',   v_new_created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.use_bump_ticket(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.use_bump_ticket(bigint) TO authenticated;


-- ─────────────────────────────────────────────
-- 6. 인덱스
-- ─────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_shop_items_item_key ON public.shop_items (item_key);


-- ─────────────────────────────────────────────
-- 7. shop_items SELECT 정책 — admin/staff는 hidden 상품도 미리보기 가능
--    (범프 티켓처럼 실서비스에는 숨기되, 개발자는 계속 확인/테스트해야 하는
--     상품을 위한 일반 정책 개선. shop_items 전체에 적용되며 특정 상품에
--     국한되지 않음. 기존 events_setup.sql의 관리자 판별 방식과 동일)
-- ─────────────────────────────────────────────

DROP POLICY IF EXISTS "shop_items: select" ON public.shop_items;
CREATE POLICY "shop_items: select"
  ON public.shop_items FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (
      status != 'hidden'
      OR ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text) IN ('admin', 'staff')
    )
  );


-- ─────────────────────────────────────────────
-- 8. 가격/할인 확정값 반영 (2026-07-09)
--    이 스크립트를 이미 한 번 실행해서 위 INSERT가 999999999 placeholder로
--    들어간 상태라면, ON CONFLICT DO UPDATE가 price/original_price/discount_note를
--    일부러 갱신 대상에서 제외하기 때문에 재실행만으로는 값이 안 바뀝니다.
--    그래서 별도 UPDATE로 확정값을 반영합니다. (이미 이 값이 들어있어도 재실행 안전)
-- ─────────────────────────────────────────────

UPDATE public.shop_items SET price = 30,  original_price = NULL, discount_note = NULL
  WHERE item_key = 'ticket-bump' AND grant_qty = 1;

UPDATE public.shop_items SET price = 135, original_price = 150, discount_note = '10% 할인'
  WHERE item_key = 'ticket-bump' AND grant_qty = 5;

UPDATE public.shop_items SET price = 255, original_price = 300, discount_note = '15% 할인'
  WHERE item_key = 'ticket-bump' AND grant_qty = 10;
