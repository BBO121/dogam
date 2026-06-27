-- ============================================================
-- notifications.user_nickname → NULL 허용으로 변경
-- user_id 컬럼이 추가된 이후 user_nickname 없이도 알림 수신 가능하게 전환
-- ============================================================

ALTER TABLE public.notifications
ALTER COLUMN user_nickname DROP NOT NULL;
