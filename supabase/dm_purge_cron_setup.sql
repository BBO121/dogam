-- ============================================
-- dm_purge_cron_setup.sql — 채팅 이미지 30일 자동삭제 Cron 등록
-- 작성일: 2026-08-13
--
-- ⚠️ 상태: DRAFT — 검토 후 실행하세요.
--
-- 전제:
--   - supabase/functions/purge-expired-chat-images 는 이미 배포 완료 (CLI로 배포함)
--   - CRON_SECRET Edge Function 시크릿도 이미 설정 완료 (CLI로 설정함)
--   - 아래 vault.create_secret에 넣는 값은 그 CRON_SECRET과 반드시 동일해야 함
-- ============================================

-- 1) 확장 활성화 (pg_available_extensions 확인 결과 둘 다 설치 안 된 상태였음)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 2) CRON_SECRET을 Vault에 저장 — pg_cron 잡 본문에 시크릿 원문이 그대로 남지 않도록
--    이름으로 참조해서 쓴다. 아래 '__REPLACE_WITH_CRON_SECRET__' 자리에 CLI로 설정한
--    CRON_SECRET과 동일한 값을 넣고 실행할 것.
select vault.create_secret('__REPLACE_WITH_CRON_SECRET__', 'dm_purge_cron_secret');

-- 3) 매일 1회, 04:00 KST(=19:00 UTC) 실행
select cron.schedule(
  'dm-purge-expired-chat-images',
  '0 19 * * *',
  $$
  select net.http_post(
    url := 'https://tnvkfcqphdxdyvswbkfe.functions.supabase.co/purge-expired-chat-images',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'dm_purge_cron_secret'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- ============================================
-- 등록 상태 확인 (읽기 전용)
-- ============================================
-- select jobid, jobname, schedule, active from cron.job where jobname = 'dm-purge-expired-chat-images';

-- ============================================
-- Rollback
-- ============================================
-- select cron.unschedule('dm-purge-expired-chat-images');
-- select vault.delete_secret((select id from vault.secrets where name = 'dm_purge_cron_secret'));
