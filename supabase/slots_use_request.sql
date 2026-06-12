-- slots 테이블에 사용 요청 관련 컬럼 추가
-- use_request_status: 'none' | 'pending' | 'approved' | 'rejected'

ALTER TABLE public.slots
  ADD COLUMN IF NOT EXISTS use_request_status text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS use_requested_at   timestamptz;
