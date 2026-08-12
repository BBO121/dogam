-- dm_verify_readonly.sql — 읽기 전용 진단 쿼리 (실행해도 데이터 변경 없음)
-- dm_setup.sql 적용 결과 최종 확인용

select 'bucket' as kind, id as name, public::text as detail1,
       file_size_limit::text as detail2, allowed_mime_types::text as detail3
from storage.buckets where id = 'chat-attachments'

union all

select 'realtime_publication', tablename, 'registered', null, null
from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dm_messages'

union all

select 'rls_enabled', relname, relrowsecurity::text, null, null
from pg_class
where relname in ('dm_rooms','dm_room_reads','dm_messages','dm_message_attachments','dm_blocks')

union all

select 'policy', tablename || ' / ' || policyname, cmd, null, null
from pg_policies
where schemaname = 'public' and tablename like 'dm_%'

union all

select 'storage_policy', policyname, cmd, null, null
from pg_policies
where schemaname = 'storage' and tablename = 'objects' and policyname like 'chat_attachments%'

union all

select 'trigger', tgname, tgrelid::regclass::text, null, null
from pg_trigger
where tgname like 'dm_%' and not tgisinternal

order by 1, 2;
