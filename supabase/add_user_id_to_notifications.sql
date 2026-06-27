-- ============================================================
-- [STEP 1] notifications 테이블에 user_id 컬럼 추가
-- Supabase SQL Editor에서 가장 먼저 실행하세요.
-- ============================================================

-- 1. user_id 컬럼 추가 (nullable — 기존 데이터 보존)
ALTER TABLE public.notifications
ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

-- 2. 조회·realtime 필터 성능을 위한 인덱스
CREATE INDEX IF NOT EXISTS idx_notifications_user_id
ON public.notifications(user_id);

-- 3. 기존 알림 backfill: user_nickname → user_id 매핑
--    display_name 또는 nickname이 user_nickname과 일치하는 행에 user_id 채우기
UPDATE public.notifications n
SET user_id = u.id
FROM auth.users u
WHERE n.user_id IS NULL
  AND (
    u.raw_user_meta_data->>'display_name' = n.user_nickname
    OR u.raw_user_meta_data->>'nickname'  = n.user_nickname
  );
