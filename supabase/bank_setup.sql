-- ══════════════════════════════════════════════
--  종족연구소 2.0 — 재화/지갑 시스템 셋업 SQL
--  실행 순서: 1 → 2 → 3 → 4 → 5 → 6
-- ══════════════════════════════════════════════


-- ── 1. user_wallets 테이블 ───────────────────

CREATE TABLE IF NOT EXISTS public.user_wallets (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid        NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  research_records  integer     NOT NULL DEFAULT 0 CHECK (research_records >= 0),
  keys              integer     NOT NULL DEFAULT 0 CHECK (keys >= 0),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_wallets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "wallets_select_own"  ON public.user_wallets;
DROP POLICY IF EXISTS "wallets_insert_none" ON public.user_wallets;

-- 본인 지갑만 조회 가능
CREATE POLICY "wallets_select_own"
  ON public.user_wallets FOR SELECT
  USING (auth.uid() = user_id);

-- 직접 INSERT/UPDATE/DELETE 금지 (RPC/트리거로만 처리)


-- ── 2. currency_logs 테이블 ─────────────────

CREATE TABLE IF NOT EXISTS public.currency_logs (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type                  text        NOT NULL,
  source                text        NOT NULL,
  currency              text        NOT NULL DEFAULT 'research_records',
  amount                integer     NOT NULL CHECK (amount > 0),
  balance_after         integer     NOT NULL,
  counterpart_user_id   uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  counterpart_nickname  text,
  note                  text,
  created_at            timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.currency_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "logs_select_own" ON public.currency_logs;

-- 본인 로그만 조회 가능
CREATE POLICY "logs_select_own"
  ON public.currency_logs FOR SELECT
  USING (auth.uid() = user_id);

-- 직접 INSERT/UPDATE/DELETE 금지 (RPC/트리거로만 처리)


-- ── 3. 가입 시 지갑 자동 생성 트리거 ─────────
--  새 유저가 생성되면 지갑을 만들고 가입 보너스 100 연구기록을 지급합니다.

CREATE OR REPLACE FUNCTION public.handle_new_user_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 지갑 생성 (가입 보너스 100 포함)
  INSERT INTO public.user_wallets (user_id, research_records, keys)
  VALUES (NEW.id, 100, 0);

  -- 가입 보너스 로그
  INSERT INTO public.currency_logs
    (user_id, type, source, currency, amount, balance_after, note)
  VALUES
    (NEW.id, 'signup_bonus', 'signup', 'research_records', 100, 100, '가입을 환영합니다!');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_wallet();


-- ── 4. RPC: transfer_research_records ────────
--  연구기록 유저 간 전송. 원자적 처리 보장.

CREATE OR REPLACE FUNCTION public.transfer_research_records(
  p_to_nickname text,
  p_amount      integer,
  p_note        text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_id         uuid := auth.uid();
  v_to_id           uuid;
  v_to_nickname     text;
  v_from_balance    integer;
  v_from_new_bal    integer;
  v_to_new_bal      integer;
BEGIN
  -- 로그인 확인
  IF v_from_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 전송량 유효성
  IF p_amount < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT');
  END IF;

  -- 수신자 조회 (닉네임 → UUID)
  SELECT id, raw_user_meta_data->>'nickname'
  INTO v_to_id, v_to_nickname
  FROM auth.users
  WHERE raw_user_meta_data->>'nickname' = p_to_nickname
     OR raw_user_meta_data->>'display_name' = p_to_nickname
  LIMIT 1;

  IF v_to_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  -- 자기 자신 전송 방지
  IF v_from_id = v_to_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'SELF_TRANSFER');
  END IF;

  -- 발신자 잔액 확인 (FOR UPDATE로 동시성 보호)
  SELECT research_records INTO v_from_balance
  FROM public.user_wallets
  WHERE user_id = v_from_id
  FOR UPDATE;

  IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
  END IF;

  -- 발신자 잔액 차감
  v_from_new_bal := v_from_balance - p_amount;
  UPDATE public.user_wallets
  SET research_records = v_from_new_bal, updated_at = now()
  WHERE user_id = v_from_id;

  -- 수신자 잔액 증가 (FOR UPDATE)
  SELECT research_records INTO v_to_new_bal
  FROM public.user_wallets
  WHERE user_id = v_to_id
  FOR UPDATE;

  v_to_new_bal := COALESCE(v_to_new_bal, 0) + p_amount;
  UPDATE public.user_wallets
  SET research_records = v_to_new_bal, updated_at = now()
  WHERE user_id = v_to_id;

  -- 발신자 로그
  INSERT INTO public.currency_logs
    (user_id, type, source, currency, amount, balance_after, counterpart_user_id, counterpart_nickname, note)
  VALUES
    (v_from_id, 'transfer_send', 'transfer', 'research_records', p_amount, v_from_new_bal, v_to_id, v_to_nickname, p_note);

  -- 수신자 로그
  INSERT INTO public.currency_logs
    (user_id, type, source, currency, amount, balance_after, counterpart_user_id, counterpart_nickname, note)
  VALUES
    (v_to_id, 'transfer_receive', 'transfer', 'research_records', p_amount, v_to_new_bal, v_from_id,
     (SELECT raw_user_meta_data->>'display_name' FROM auth.users WHERE id = v_from_id),
     p_note);

  RETURN jsonb_build_object('success', true, 'new_balance', v_from_new_bal);
END;
$$;


-- ── 5. 기존 유저 Backfill ────────────────────
--  트리거 생성 이전에 가입한 유저에게 지갑과 가입 보너스를 소급 적용합니다.
--  이미 지갑이 있는 유저는 건너뜁니다.

INSERT INTO public.user_wallets (user_id, research_records, keys)
SELECT id, 100, 0
FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_wallets)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.currency_logs
  (user_id, type, source, currency, amount, balance_after, note)
SELECT
  u.id,
  'signup_bonus',
  'signup',
  'research_records',
  100,
  100,
  '가입을 환영합니다! (소급 지급)'
FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1 FROM public.currency_logs cl
  WHERE cl.user_id = u.id AND cl.type = 'signup_bonus'
);


-- ── 6. 인덱스 ────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_currency_logs_user_id    ON public.currency_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_currency_logs_created_at ON public.currency_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_currency_logs_type       ON public.currency_logs (type);
CREATE INDEX IF NOT EXISTS idx_currency_logs_source     ON public.currency_logs (source);


-- ══════════════════════════════════════════════
--  완료. Supabase SQL Editor에서 순서대로 실행하세요.
-- ══════════════════════════════════════════════
