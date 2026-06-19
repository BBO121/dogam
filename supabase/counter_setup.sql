-- ══════════════════════════════════════════════
--  user_achievement_counters 테이블 + RPC 생성
--  Supabase SQL Editor에서 실행하세요.
-- ══════════════════════════════════════════════

-- ── 테이블 생성 ──────────────────────────────
CREATE TABLE IF NOT EXISTS user_achievement_counters (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  counter_key text NOT NULL,
  count       integer NOT NULL DEFAULT 1,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, counter_key)
);

-- ── RLS 설정 ─────────────────────────────────
ALTER TABLE user_achievement_counters ENABLE ROW LEVEL SECURITY;

-- 본인 카운터만 조회 가능
CREATE POLICY "counters_select_own"
  ON user_achievement_counters FOR SELECT
  USING (auth.uid() = user_id);

-- 본인 카운터만 삽입 가능
CREATE POLICY "counters_insert_own"
  ON user_achievement_counters FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 본인 카운터만 수정 가능
CREATE POLICY "counters_update_own"
  ON user_achievement_counters FOR UPDATE
  USING (auth.uid() = user_id);

-- ── RPC: 카운터 증가 후 새 count 반환 ─────────
-- SECURITY DEFINER: 원자적 upsert 보장, auth.uid()로 본인만 수정 가능
CREATE OR REPLACE FUNCTION increment_achievement_counter(p_counter_key TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   uuid := auth.uid();
  v_new_count integer;
BEGIN
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  INSERT INTO user_achievement_counters (user_id, counter_key, count, updated_at)
  VALUES (v_user_id, p_counter_key, 1, now())
  ON CONFLICT (user_id, counter_key)
  DO UPDATE SET
    count      = user_achievement_counters.count + 1,
    updated_at = now()
  RETURNING count INTO v_new_count;

  RETURN v_new_count;
END;
$$;
