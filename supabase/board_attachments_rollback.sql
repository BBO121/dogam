-- ============================================
-- board_attachments.sql 되돌리기 (첨부 시스템 폐기)
-- 대상: 공지사항(notices) / 이벤트(events) / 업데이트(update_notes) / 개발일지(dev_logs)
-- 작성일: 2026-07-27
--
-- board_attachments.sql을 Supabase에서 이미 실행한 경우에만 실행하세요.
-- 실행한 적이 없다면 이 파일도 실행할 필요 없습니다.
--
-- 주의: attachments 컬럼에 실제로 업로드된 파일이 있다면(=이 기능으로
-- 첨부를 저장해본 적이 있다면) 아래 2번 단계에서 해당 Storage 파일이
-- 함께 삭제됩니다. 게시글 자체(title/content 등)는 영향받지 않습니다.
-- ============================================

-- 1. Storage RLS 정책 제거
DROP POLICY IF EXISTS "board_attachments_public_select" ON storage.objects;
DROP POLICY IF EXISTS "board_attachments_staff_insert"   ON storage.objects;
DROP POLICY IF EXISTS "board_attachments_staff_update"   ON storage.objects;
DROP POLICY IF EXISTS "board_attachments_staff_delete"   ON storage.objects;

-- 2. board-attachments 버킷 내 객체 삭제 후 버킷 삭제
DELETE FROM storage.objects WHERE bucket_id = 'board-attachments';
DELETE FROM storage.buckets WHERE id = 'board-attachments';

-- 3. attachments 컬럼 제거 (게시글 본문/제목 등 다른 컬럼은 영향 없음)
ALTER TABLE public.notices      DROP COLUMN IF EXISTS attachments;
ALTER TABLE public.events       DROP COLUMN IF EXISTS attachments;
ALTER TABLE public.update_notes DROP COLUMN IF EXISTS attachments;
ALTER TABLE public.dev_logs     DROP COLUMN IF EXISTS attachments;
