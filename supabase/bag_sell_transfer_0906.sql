-- ============================================================
-- [FEATURE] 내 가방 — 아이템 판매 + 아이템 전송 (1차)
-- 작성일: 2026-09-06
--
-- 범위: 아이템 상세 모달(#bagItemInfoModal)에서
--   (1) 보유 아이템을 연구기록으로 되팔기(sell_item RPC)
--   (2) 다른 유저에게 보유 아이템 전송(transfer_item RPC)
--   다른 페이지/상점 기능은 건드리지 않는다. 상점 구매(purchase_shop_item),
--   조합(craft_labber_subject), 탐험 드랍은 무수정.
--
-- ── 하는 일 ────────────────────────────────────────────────
--   STEP 0. 선행 스키마 가드
--   STEP 1. items.is_sellable(3-state) + items.sell_price(수동 판매가 컬럼)
--   STEP 2. 판매/전송 가능 아이템 지정  ★뽀 확인 후 실행 — 목록 조정 가능★
--   STEP 3. public.sell_item(p_item_code text, p_quantity int)          RPC
--   STEP 4. public.transfer_item(...) RPC  — item_logs metadata 에 counterpart_nickname 스냅샷 추가
--   STEP 5. public.get_my_item_transfer_logs(p_limit, p_offset, p_filter)  — 본인 전송 로그 조회 (신규 테이블 없음, item_logs 재사용)
--   STEP 6. GRANT / REVOKE
--   STEP 7. 진단 / 검증 쿼리 (주석)
--
-- ── 판매가 정책 (아이템 대장 "판매가" 열 기준 — 뽀 확정 2026-09-06) ──────
--   개당 판매가 = COALESCE(
--                  items.sell_price,                              -- (a) 수동 지정가 있으면 그대로
--                  ROUND( MIN(활성 research_records 상점가) × 0.2 / 5 ) × 5   -- (b) fallback (지금은 안 탐)
--                )
--     · 서버가 계산 — 클라이언트가 가격을 넘기지 않는다.
--     · STEP 2 에서 LABBER 아이템 전부 items.sell_price 를 명시값으로 채우므로 (b) 자동계산은 더 이상 안 탄다.
--   ── 대장 기준 판매가 ──
--     · 표준 등급 전부                       → 10 연구기록
--     · 특이 등급(rarity='labber_special')   → 30 연구기록  (8종 전부 조합소 출신 = 래버 상점 아님)
--     · 래버 상점 포드/카트리지(표준) 4종     → 20 연구기록
--     · 래버 배양 시약(labber_culture_reagent) → 판매 불가(is_sellable=false, sell_price NULL)
--
-- ── 판매/전송 가능 여부: fail-closed ──────────────────────
--   sell_item     : items.is_sellable    IS TRUE 인 아이템만 허용 (NULL / false 는 서버에서 거부)
--   transfer_item : items.is_transferable IS TRUE 인 아이템만 허용 (NULL / false 는 서버에서 거부)
--   → "정책 미정(NULL)" 아이템은 판매/전송 둘 다 자동 차단. 기존 아이템을 일괄 허용하지 않는다.
--
-- 재실행 안전(idempotent). 커밋/푸시/실행 전 뽀 확인.
-- ============================================================


-- ============================================================
-- STEP 0. 선행 스키마 가드
-- ============================================================
DO $$
BEGIN
  IF to_regclass('public.items')                IS NULL
     OR to_regclass('public.user_inventory')    IS NULL
     OR to_regclass('public.user_wallets')      IS NULL
     OR to_regclass('public.currency_logs')     IS NULL
     OR to_regclass('public.item_logs')         IS NULL
     OR to_regclass('public.item_shop_listings') IS NULL
     OR to_regprocedure('public._apply_item_delta(uuid,uuid,integer,text,text,text,jsonb,uuid)') IS NULL
  THEN
    RAISE EXCEPTION
      '[bag_sell_transfer] 선행 미실행: item_system_setup.sql / labber_shop_purchase_setup_0904.sql (+ bank_setup.sql) 를 먼저 실행하세요.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='items' AND column_name='is_transferable'
  ) THEN
    RAISE EXCEPTION
      '[bag_sell_transfer] items.is_transferable 컬럼이 없습니다 — supabase/labber_culture_reagent_settings_0906.sql STEP 1 을 먼저 실행하세요.';
  END IF;
END $$;


-- ============================================================
-- STEP 1. items.is_sellable — 판매 가능 여부 (is_transferable 과 동일한 3-state 정책)
--   NULL = 정책 미정 (판매 불가) / true = 판매 허용 / false = 명시적 판매 금지
--   판매 RPC 는 fail-closed: is_sellable IS TRUE 일 때만 허용.
-- ============================================================
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS is_sellable boolean;   -- nullable, DEFAULT 없음 (NULL 미정 / true 허용 / false 금지)

COMMENT ON COLUMN public.items.is_sellable IS
'되팔기(가방 판매) 허용 여부. NULL=정책 미정, true=허용, false=명시적 금지. '
'판매 RPC(sell_item)는 fail-closed(is_sellable IS TRUE 일 때만)로 검사한다.';

-- 수동 판매가 — 상점에서 안 파는 아이템(탐험 재료/잡템 등)의 판매가를 직접 지정할 때 사용.
--   NULL  → sell_item 이 상점가 20% × 5단위 반올림으로 자동 계산
--   정수  → 그 값을 개당 판매가로 그대로 사용 (자동 계산 무시)
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS sell_price integer;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'items_sell_price_nonneg'
  ) THEN
    ALTER TABLE public.items
      ADD CONSTRAINT items_sell_price_nonneg CHECK (sell_price IS NULL OR sell_price >= 0);
  END IF;
END $$;

COMMENT ON COLUMN public.items.sell_price IS
'수동 지정 개당 판매가(연구기록). NULL 이면 sell_item 이 상점가×20%를 5단위 반올림해 자동 계산. '
'상점 판매가 없는 탐험 재료/잡템 등에 값을 채워 판매를 연다.';


-- ============================================================
-- STEP 2. 판매/전송 가능 아이템 지정  (아이템 대장 "판매가" 열 기준 — 뽀 확정 2026-09-06)
--
--   ── 대상 범위 ──
--     code 프리픽스 dogam_ / labber_ / suspicious_ / random_ + disposable_embryo_kit
--     (= 아이템 대장에 오른 LABBER 아이템 = 내 가방에 들어갈 수 있는 아이템.
--      사이트 전역의 기존 상점 아이템/티켓 등 다른 아이템은 건드리지 않는다.)
--     대장엔 있지만 아직 public.items 에 없는 "선형 연장 카트리지" 는 자동 제외(INSERT 안 됨).
--
--   ── 판매가(sell_price) — 대장 그대로 ──
--     · 표준 등급 전부                       → 10
--     · 특이 등급(rarity='labber_special')   → 30   (전부 조합소 출신 — 래버 상점 아님)
--     · 래버 상점 포드/카트리지(표준) 4종     → 20
--     · 래버 배양 시약(labber_culture_reagent) → 판매 불가(is_sellable=false, sell_price NULL)
--         계정당 1회 구매 + is_transferable=false(계정 귀속) — 되팔기 허용 시 정책 일관성 깨짐
--
--   ── 판매 허용(is_sellable) ──
--     대상 범위 전부 true. 단 래버 배양 시약만 false.
--     sell_price 를 전부 명시값으로 채우므로 상점가×20% 자동계산 경로는 더 이상 안 탄다.
--
--   ── 전송 허용(is_transferable=true): 소모 재료 2종 + 포드/카트리지 8종 (뽀 확정 "포드 카트리지도 전송 허용").
--     labber_culture_reagent(MYO 시약)은 전송 금지 유지(false).
-- ============================================================

-- 2-1) LABBER 아이템 전체: 기본 판매가 10, 판매 허용
UPDATE public.items SET sell_price = 10, is_sellable = true
WHERE (code ~ '^(dogam|labber|suspicious|random)_' OR code = 'disposable_embryo_kit');

-- 2-2) 특이 등급 → 30 (= rarity 'labber_special' 8종. 전부 조합소 출신이라 "래버 상점 제외" 조건에 걸리는 게 없음.
--      rarity 리맵(item_dogam_ledger_sync)이 선행 안 됐을 수도 있어 code 를 명시한다.)
UPDATE public.items SET sell_price = 30
WHERE code IN (
  'labber_pod_semicircle', 'labber_pod_triangle', 'labber_pod_square', 'labber_cartridge_split',
  'random_subject', 'random_fish_subject', 'random_reptile_subject', 'random_bird_subject'
);

-- 2-3) 래버 상점 포드/카트리지(표준) → 20
UPDATE public.items SET sell_price = 20
WHERE code IN ('labber_pod_circle', 'labber_pod_cylinder',
               'labber_cartridge_protrude', 'labber_cartridge_attach');

-- 2-4) 래버 배양 시약 → 판매 불가 (sell_price 도 비운다)
UPDATE public.items SET is_sellable = false, sell_price = NULL
WHERE code = 'labber_culture_reagent';

-- 전송 허용: 소모 재료 2종 + 포드 5종 + 카트리지 3종 (= 판매 안 하는 특이등급 모듈 포함).
--   labber_culture_reagent 는 여기 없음 → false 유지.
UPDATE public.items SET is_transferable = true
WHERE code IN (
  'disposable_embryo_kit',
  'labber_empty_module',
  'labber_pod_circle', 'labber_pod_cylinder', 'labber_pod_triangle', 'labber_pod_square', 'labber_pod_semicircle',
  'labber_cartridge_protrude', 'labber_cartridge_attach', 'labber_cartridge_split'
) AND is_transferable IS DISTINCT FROM true;


-- ============================================================
-- STEP 3. public.sell_item(p_item_code text, p_quantity int DEFAULT 1)
--   보유 아이템을 연구기록으로 되판다. 판매가는 서버가 계산(items.sell_price 우선, 없으면 상점가 20%×5단위 반올림).
--
--   흐름(단일 트랜잭션):
--     1) 로그인  2) quantity 검증(>0)  3) 아이템 조회
--     4) is_sellable IS TRUE 검증 (fail-closed)
--     5) 개당 판매가 = COALESCE( items.sell_price,
--                                ROUND(MIN(활성 research_records listing.price) × 0.2 / 5) × 5 )
--        (둘 다 없거나 0 이면 NOT_SELLABLE)
--     6) _apply_item_delta(-quantity) — 내부에서 user_inventory FOR UPDATE + 보유량 검증
--        (부족하면 INSUFFICIENT_QUANTITY, 아무것도 안 바꿈)
--     7) user_wallets.research_records += 총액 (UPSERT, RETURNING 으로 잔액 확정)
--     8) currency_logs 1건 (type='item_sell', amount 양수, balance_after=지급 후 잔액)
--     9) 결과 반환
--   6~8 중 실패 시 RAISE → 전체 롤백(아이템/재화 원복).
--
--   동시성: _apply_item_delta 의 user_inventory FOR UPDATE 가 같은 유저의 같은 아이템 판매를
--   직렬화한다. 빠르게 2번 눌러도 두 번째는 최신 보유량으로 재검증 → 보유량 이상 판매 불가.
--   지갑은 상대 증분(+= 총액) + RETURNING 이라 별도 락 없이도 원자적.
-- ============================================================
CREATE OR REPLACE FUNCTION public.sell_item(
  p_item_code text,
  p_quantity  integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_item       record;
  v_base_price integer;
  v_unit       integer;
  v_total      integer;
  v_new_rr     integer;
  v_res        jsonb;
BEGIN
  -- 1) 로그인
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 2) 수량
  IF p_quantity IS NULL OR p_quantity < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_QUANTITY');
  END IF;

  -- 3) 아이템
  SELECT * INTO v_item FROM public.items WHERE code = p_item_code;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  -- 4) 판매 가능 여부 (fail-closed: NULL/false 모두 거부)
  IF v_item.is_sellable IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_SELLABLE');
  END IF;

  -- 5) 개당 판매가
  --    (a) items.sell_price 수동 지정가 우선. (b) 없으면 상점가(MIN 활성 research_records) × 20% 를 5단위 반올림.
  IF v_item.sell_price IS NOT NULL THEN
    v_unit := v_item.sell_price;
  ELSE
    SELECT MIN(l.price) INTO v_base_price
    FROM public.item_shop_listings l
    WHERE l.item_id = v_item.id
      AND l.currency = 'research_records'
      AND l.is_active = true;

    IF v_base_price IS NULL OR v_base_price <= 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_SELLABLE', 'reason', 'NO_BASE_PRICE');
    END IF;

    -- 5단위 반올림. 정수 base 라 half-case 없음. 결과는 항상 5의 배수(0,5,10,...).
    v_unit := (round(v_base_price::numeric * 0.2 / 5) * 5)::integer;
  END IF;

  IF v_unit IS NULL OR v_unit < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_SELLABLE', 'reason', 'SELL_PRICE_ZERO');
  END IF;
  v_total := v_unit * p_quantity;

  -- 6) 아이템 차감 (보유량 검증 + FOR UPDATE 는 _apply_item_delta 내부)
  v_res := public._apply_item_delta(
    p_user_id  := v_uid,
    p_item_id  := v_item.id,
    p_delta    := -p_quantity,
    p_type     := 'item_sell',
    p_source   := 'bag',
    p_note     := '가방 판매',
    p_metadata := jsonb_build_object(
      'unit_price', v_unit, 'total', v_total, 'currency', 'research_records',
      'base_price', v_base_price,
      'price_source', CASE WHEN v_item.sell_price IS NOT NULL THEN 'manual' ELSE 'shop_20pct_round5' END)
  );

  IF v_res IS NULL OR (v_res ->> 'success') IS DISTINCT FROM 'true' THEN
    -- 보유량 부족 등 — _apply_item_delta 가 아무것도 안 바꾼 상태
    RETURN jsonb_build_object(
      'success', false,
      'error',   COALESCE(v_res ->> 'error', 'SELL_FAILED'),
      'have',    (v_res ->> 'current')
    );
  END IF;

  -- 7) 재화 지급 (UPSERT — 지갑 없는 계정 방어)
  INSERT INTO public.user_wallets (user_id, research_records, keys, updated_at)
  VALUES (v_uid, v_total, 0, now())
  ON CONFLICT (user_id) DO UPDATE
  SET research_records = public.user_wallets.research_records + v_total,
      updated_at       = now()
  RETURNING research_records INTO v_new_rr;

  -- 8) 재화 로그 (amount 는 항상 양수 — 이 프로젝트 규칙. 방향은 type + balance_after)
  INSERT INTO public.currency_logs (user_id, type, source, currency, amount, balance_after, note)
  VALUES (v_uid, 'item_sell', 'bag', 'research_records', v_total, v_new_rr,
          v_item.name || ' 판매 (' || p_quantity || '개)');

  -- 9) 결과
  RETURN jsonb_build_object(
    'success',             true,
    'item_code',           v_item.code,
    'item_name',           v_item.name,
    'sold',                p_quantity,
    'unit_price',          v_unit,
    'total',               v_total,
    'currency',            'research_records',
    'new_research_records', v_new_rr,
    'quantity',            (v_res ->> 'quantity')::int
  );
END;
$$;


-- ============================================================
-- STEP 4. public.transfer_item(p_item_code text, p_receiver_user_id uuid, p_quantity int DEFAULT 1)
--   보유 아이템을 다른 유저에게 넘긴다. 재화 이동 없음.
--
--   검증: 1) 로그인  2) receiver 존재 + 본인 아님  3) quantity>0  4) 아이템 존재
--         5) is_transferable IS TRUE (fail-closed)  6) receiver 가 실제 auth.users 에 있고 미탈퇴
--         7) 보내는 사람 보유량 >= quantity
--
--   흐름(단일 트랜잭션):
--     - 양쪽 user_inventory row 확보 후 user_id 오름차순으로 FOR UPDATE (교차 전송 데드락 방지)
--     - _apply_item_delta(sender, -q, 'transfer_send',  counterpart=receiver)
--     - _apply_item_delta(receiver, +q, 'transfer_receive', counterpart=sender)
--     - (best-effort) receiver 에게 알림. 알림 실패는 전송을 롤백하지 않는다.
--   하나라도 실패하면 전체 롤백.
--
--   동시성: 위 정렬 FOR UPDATE 로 같은 아이템의 동시 전송을 직렬화 + 데드락 방지.
--   _apply_item_delta 의 보유량 검증이 최종 방어선(보유량 이상 전송 불가).
-- ============================================================
CREATE OR REPLACE FUNCTION public.transfer_item(
  p_item_code        text,
  p_receiver_user_id uuid,
  p_quantity         integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_item      record;
  v_recv_nick text;
  v_send_nick text;
  v_res_out   jsonb;
  v_res_in    jsonb;
BEGIN
  -- 1) 로그인
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 2) 인자
  IF p_receiver_user_id IS NULL OR p_item_code IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ARGS');
  END IF;
  IF p_receiver_user_id = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'SELF_TRANSFER');
  END IF;
  IF p_quantity IS NULL OR p_quantity < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_QUANTITY');
  END IF;

  -- 3) 아이템
  SELECT * INTO v_item FROM public.items WHERE code = p_item_code;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  -- 4) 전송 가능 여부 (fail-closed)
  IF v_item.is_transferable IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_TRANSFERABLE');
  END IF;

  -- 5) 받는 유저 존재 확인 + 양쪽 닉네임 스냅샷 (로그 metadata 에 당시 값으로 박아둔다 — 나중에 닉 바뀌어도 보존)
  SELECT COALESCE(
           NULLIF(TRIM(raw_user_meta_data->>'display_name'), ''),
           NULLIF(TRIM(raw_user_meta_data->>'nickname'), ''),
           '(알 수 없음)')
    INTO v_recv_nick
  FROM auth.users
  WHERE id = p_receiver_user_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'RECEIVER_NOT_FOUND');
  END IF;

  SELECT COALESCE(
           NULLIF(TRIM(raw_user_meta_data->>'display_name'), ''),
           NULLIF(TRIM(raw_user_meta_data->>'nickname'), ''),
           '(알 수 없음)')
    INTO v_send_nick
  FROM auth.users WHERE id = v_uid;

  -- 6) 양쪽 인벤토리 row 확보 + 정렬 잠금 (데드락 방지)
  INSERT INTO public.user_inventory (user_id, item_id, quantity)
  VALUES (v_uid, v_item.id, 0) ON CONFLICT (user_id, item_id) DO NOTHING;
  INSERT INTO public.user_inventory (user_id, item_id, quantity)
  VALUES (p_receiver_user_id, v_item.id, 0) ON CONFLICT (user_id, item_id) DO NOTHING;

  PERFORM 1 FROM public.user_inventory
  WHERE item_id = v_item.id AND user_id IN (v_uid, p_receiver_user_id)
  ORDER BY user_id
  FOR UPDATE;

  -- 7) 보내는 사람 차감
  v_res_out := public._apply_item_delta(
    p_user_id  := v_uid,
    p_item_id  := v_item.id,
    p_delta    := -p_quantity,
    p_type     := 'transfer_send',
    p_source   := 'bag_transfer',
    p_note     := '아이템 전송',
    p_metadata := jsonb_build_object(
      'counterpart_user_id',  p_receiver_user_id,   -- 상대방(uuid) — item_logs.counterpart_user_id 컬럼에도 동일 저장
      'counterpart_nickname', v_recv_nick,          -- 전송 당시 상대방 닉네임 스냅샷
      'quantity',             p_quantity),
    p_counterpart_user_id := p_receiver_user_id
  );
  IF v_res_out IS NULL OR (v_res_out ->> 'success') IS DISTINCT FROM 'true' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   COALESCE(v_res_out ->> 'error', 'TRANSFER_FAILED'),
      'have',    (v_res_out ->> 'current')
    );
  END IF;

  -- 8) 받는 사람 지급
  v_res_in := public._apply_item_delta(
    p_user_id  := p_receiver_user_id,
    p_item_id  := v_item.id,
    p_delta    := p_quantity,
    p_type     := 'transfer_receive',
    p_source   := 'bag_transfer',
    p_note     := '아이템 수령',
    p_metadata := jsonb_build_object(
      'counterpart_user_id',  v_uid,        -- 상대방(보낸 사람) uuid
      'counterpart_nickname', v_send_nick,  -- 전송 당시 보낸 사람 닉네임 스냅샷
      'quantity',             p_quantity),
    p_counterpart_user_id := v_uid
  );
  IF v_res_in IS NULL OR (v_res_in ->> 'success') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'transfer_item: receiver grant failed (item=%, to=%, res=%)',
      p_item_code, p_receiver_user_id, v_res_in;
  END IF;

  -- 9) 알림 (best-effort — 실패해도 전송은 유지)
  BEGIN
    PERFORM public.notify_user_by_id(
      p_user_id := p_receiver_user_id,
      p_type    := 'item_transfer_received',
      p_message := v_send_nick || '님이 ' || v_item.name || ' ' || p_quantity || '개를 보냈어요.',
      p_link    := 'my-bag.html'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- 10) 결과
  RETURN jsonb_build_object(
    'success',           true,
    'item_code',         v_item.code,
    'item_name',         v_item.name,
    'quantity',          p_quantity,
    'receiver_user_id',  p_receiver_user_id,
    'receiver_nickname', v_recv_nick,
    'sender_quantity',   (v_res_out ->> 'quantity')::int
  );
END;
$$;


-- ============================================================
-- STEP 5. public.get_my_item_transfer_logs(p_limit int, p_offset int, p_filter text)
--   현재 로그인 유저 본인의 아이템 전송 내역(보낸/받은)만 반환한다.
--   새 로그 테이블 없음 — 기존 item_logs(type='transfer_send'/'transfer_receive') 를 그대로 읽는다.
--
--   보안:
--     · v_uid := auth.uid() 로 본인만. p_* 인자에 user_id 를 받지 않으므로 남의 로그 조회 불가.
--     · SECURITY DEFINER + search_path=public 고정. anon REVOKE, authenticated 만 EXECUTE.
--     · 반환값에 uuid/email 등 내부 식별자 없음 — 상대방은 "닉네임"만.
--
--   상대방 닉네임: metadata.counterpart_nickname(전송 당시 스냅샷) 우선,
--     없으면(구 로그) counterpart_user_id 로 auth.users 현재 닉 조회, 그것도 없으면 '(알 수 없음)'.
--
--   정렬: created_at DESC. 페이지네이션: LIMIT/OFFSET (p_limit 1~50, 기본 20). total_count 동봉.
--   p_filter: 'all'(기본) | 'send' | 'receive'.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_item_transfer_logs(
  p_limit  integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_filter text    DEFAULT 'all'
)
RETURNS TABLE (
  log_id               bigint,
  direction            text,          -- 'send' | 'receive'
  item_name            text,
  quantity             integer,
  counterpart_nickname text,
  created_at           timestamptz,
  total_count          bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid    := auth.uid();
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_types  text[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN;   -- 로그인 안 됨 → 빈 결과
  END IF;

  v_types := CASE lower(COALESCE(p_filter, 'all'))
    WHEN 'send'    THEN ARRAY['transfer_send']
    WHEN 'receive' THEN ARRAY['transfer_receive']
    ELSE               ARRAY['transfer_send', 'transfer_receive']
  END;

  -- CTE 컬럼 별칭은 RETURNS TABLE 의 OUT 파라미터명과 겹치지 않게 r_ 프리픽스 (plpgsql 이름 충돌 방지).
  -- RETURN QUERY 는 컬럼을 "위치" 기준으로 매핑한다.
  RETURN QUERY
  WITH mine AS (
    SELECT
      l.id AS r_log_id,
      (CASE WHEN l.type = 'transfer_send' THEN 'send' ELSE 'receive' END) AS r_direction,
      COALESCE(i.name, '(삭제된 아이템)') AS r_item_name,
      abs(l.delta) AS r_quantity,
      COALESCE(
        NULLIF(TRIM(l.metadata ->> 'counterpart_nickname'), ''),
        NULLIF(TRIM(cu.raw_user_meta_data ->> 'display_name'), ''),
        NULLIF(TRIM(cu.raw_user_meta_data ->> 'nickname'), ''),
        '(알 수 없음)'
      ) AS r_nick,
      l.created_at AS r_created_at
    FROM public.item_logs l
    LEFT JOIN public.items i  ON i.id  = l.item_id
    LEFT JOIN auth.users  cu  ON cu.id = l.counterpart_user_id
    WHERE l.user_id = v_uid
      AND l.type = ANY (v_types)
  )
  SELECT m.r_log_id, m.r_direction, m.r_item_name, m.r_quantity, m.r_nick, m.r_created_at,
         count(*) OVER () AS r_total
  FROM mine m
  ORDER BY m.r_created_at DESC, m.r_log_id DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;


-- ============================================================
-- STEP 6. GRANT / REVOKE
--   _apply_item_delta 는 이미 PUBLIC/anon/authenticated 전부 REVOKE — DEFINER 함수 내부에서만 호출.
-- ============================================================
REVOKE ALL ON FUNCTION public.sell_item(text,integer)                       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.transfer_item(text,uuid,integer)              FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_item_transfer_logs(integer,integer,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sell_item(text,integer)                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_item(text,uuid,integer)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_item_transfer_logs(integer,integer,text) TO authenticated;


-- ============================================================
-- STEP 7. 진단 / 검증 (선택 실행)
-- ============================================================
-- item_logs 에 transfer_send/transfer_receive 를 다른 기능이 쓰는지 (기대: bag_transfer 만):
-- SELECT type, source, count(*) FROM public.item_logs
--  WHERE type IN ('transfer_send','transfer_receive') GROUP BY type, source;
--
-- 로그인 세션에서 내 전송 로그 (최신 20건):
-- SELECT * FROM public.get_my_item_transfer_logs(20, 0, 'all');
-- SELECT * FROM public.get_my_item_transfer_logs(20, 0, 'send');
-- SELECT * FROM public.get_my_item_transfer_logs(20, 20, 'all');   -- 다음 페이지
--   → 반환 컬럼: log_id, direction('send'/'receive'), item_name, quantity, counterpart_nickname, created_at, total_count
--   → uuid/email 없음.
--
-- 판매/전송 정책 현황:
-- SELECT code, name, is_sellable, is_transferable, sell_price
--   FROM public.items
--  WHERE is_sellable IS NOT NULL OR is_transferable IS NOT NULL OR sell_price IS NOT NULL
--  ORDER BY code;
--
-- 판매가 미리보기(sell_item 실제 계산식과 동일 — 수동가 우선, 없으면 상점가 20% 5단위 반올림):
-- SELECT i.code, i.name, i.is_sellable, i.sell_price,
--        b.base_price,
--        COALESCE(i.sell_price, (round(b.base_price::numeric * 0.2 / 5) * 5)::int) AS effective_sell_price
--   FROM public.items i
--   LEFT JOIN LATERAL (
--     SELECT MIN(l.price) AS base_price FROM public.item_shop_listings l
--      WHERE l.item_id = i.id AND l.currency='research_records' AND l.is_active=true
--   ) b ON true
--  WHERE i.is_sellable = true
--  ORDER BY i.code;
--
-- is_sellable=true 인데 sell_price 도 없고 활성 listing 도 없는 아이템 (기대: 0행 — STEP 2 에서 전부 sell_price 채움):
-- SELECT i.code FROM public.items i
--  WHERE i.is_sellable = true
--    AND i.sell_price IS NULL
--    AND NOT EXISTS (
--      SELECT 1 FROM public.item_shop_listings l
--       WHERE l.item_id = i.id AND l.currency='research_records' AND l.is_active=true);
--
-- 대장 기준 판매가 분포 확인 (기대: 10=대다수 / 20=4종 / 30=8종 / NULL+is_sellable=false=1종):
-- SELECT sell_price, is_sellable, count(*) FROM public.items
--  WHERE code ~ '^(dogam|labber|suspicious|random)_' OR code = 'disposable_embryo_kit'
--  GROUP BY sell_price, is_sellable ORDER BY sell_price NULLS LAST;
--
-- 로그인 세션에서 판매 테스트:
-- SELECT public.sell_item('disposable_embryo_kit', 1);   -- { success:true, unit_price:10, total:10, ... }
-- SELECT public.sell_item('labber_culture_reagent', 1);  -- { success:false, error:'NOT_SELLABLE' }
--
-- 로그인 세션에서 전송 테스트(대상 uuid 는 search_users 로 조회):
-- SELECT public.transfer_item('labber_empty_module', '<받는사람 uuid>', 1);
-- SELECT public.transfer_item('labber_culture_reagent', '<uuid>', 1);  -- error NOT_TRANSFERABLE
-- SELECT public.transfer_item('labber_empty_module', auth.uid(), 1);   -- error SELF_TRANSFER
--
-- 로그 확인:
-- SELECT type, source, delta, balance_after, counterpart_user_id, metadata
--   FROM public.item_logs WHERE user_id = auth.uid() ORDER BY created_at DESC LIMIT 5;
-- SELECT type, source, currency, amount, balance_after, note
--   FROM public.currency_logs WHERE user_id = auth.uid() ORDER BY created_at DESC LIMIT 5;
-- ============================================================
