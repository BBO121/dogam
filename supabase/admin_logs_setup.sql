-- =============================================
-- admin_logs 테이블 생성
-- Supabase Dashboard > SQL Editor에서 1회 실행
-- =============================================

CREATE TABLE IF NOT EXISTS admin_logs (
  id             UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id       UUID        NOT NULL,
  admin_nickname TEXT        NOT NULL,
  action_type    TEXT        NOT NULL,   -- 'password_reset', 'role_grant', 'role_revoke', ...
  target_type    TEXT,                   -- 'user', 'species', 'character', 'adoption', ...
  target_id      TEXT,                   -- 대상 ID (UUID를 TEXT로 저장해 유연성 확보)
  target_name    TEXT,                   -- 사람이 읽기 쉬운 대상 이름
  details        JSONB       DEFAULT '{}',
  created_at     TIMESTAMPTZ DEFAULT now()
);

-- 최신순 조회 인덱스
CREATE INDEX IF NOT EXISTS admin_logs_created_at_idx ON admin_logs (created_at DESC);

-- RLS 활성화
ALTER TABLE admin_logs ENABLE ROW LEVEL SECURITY;

-- 기존 정책 제거 후 재생성 (중복 에러 방지)
DROP POLICY IF EXISTS "admin_staff_select_logs" ON admin_logs;
DROP POLICY IF EXISTS "admin_staff_insert_logs" ON admin_logs;

-- 관리자/스태프만 조회 가능
-- role은 auth.users.raw_user_meta_data 기준
CREATE POLICY "admin_staff_select_logs" ON admin_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE auth.users.id = auth.uid()
        AND auth.users.raw_user_meta_data->>'role' IN ('admin', 'staff')
    )
  );

-- 관리자/스태프가 프론트엔드에서 직접 삽입 가능
-- (Edge Function은 service_role로 RLS 우회하므로 별도 정책 불필요)
CREATE POLICY "admin_staff_insert_logs" ON admin_logs
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE auth.users.id = auth.uid()
        AND auth.users.raw_user_meta_data->>'role' IN ('admin', 'staff')
    )
  );
