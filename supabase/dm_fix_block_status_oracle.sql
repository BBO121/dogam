-- ============================================
-- dm_fix_block_status_oracle.sql — is_dm_blocked_between RPC 직접 호출로 인한
--                                   "상대가 나를 차단했는지" 추론 가능 문제 수정
-- 작성일: 2026-08-12
--
-- ⚠️ 상태: DRAFT — 아직 실행하지 마세요.
--   dm_setup.sql, dm_fix_bidirectional_block.sql, dm_fix_last_message_preview.sql은
--   이미 운영 DB에 적용된 상태이므로 전체를 재실행하지 않고, 이 파일(수정분)만
--   별도로 검토 후 실행합니다.
--
-- ── 실행 전 필수 확인 사항 (뽀가 직접 확인) ──────────────────
-- Supabase Dashboard → Project Settings → API → "Exposed schemas"에
-- private가 추가되어 있지 않은지 반드시 먼저 확인할 것. private는 이 프로젝트에서
-- 앞으로도 Data API(PostgREST)에 절대 노출하지 않는 내부 전용 스키마로 사용한다.
-- 이 전제가 깨지면(즉 private가 Exposed schemas에 추가되면) 아래 수정은 무의미해지고
-- is_dm_blocked_between이 다시 /rest/v1/rpc/is_dm_blocked_between로 직접 호출 가능해진다.
--
-- ── 버그 원인 (dm_fix_bidirectional_block.sql 기준) ────────────
-- is_dm_blocked_between(uuid, uuid)는 dm_messages_insert 정책에서 양방향 차단을
-- 검사하려고 만든 SECURITY DEFINER 헬퍼인데, public 스키마에 있고 authenticated에게
-- EXECUTE가 열려 있어서 Supabase가 이를 /rest/v1/rpc/is_dm_blocked_between로
-- 자동 노출한다. 즉 어떤 유저든 sb.rpc('is_dm_blocked_between', {p_user_1: 본인,
-- p_user_2: 상대})를 브라우저 콘솔에서 직접 호출할 수 있다.
--
-- 함수 내부의 "auth.uid()가 그 쌍에 포함될 때만 답변" 가드는 임의의 제3자 쌍 탐색은
-- 막지만, 호출자 본인이 그 쌍의 당사자인 경우는 막지 못한다. 함수가 반환하는 값은
-- "(내가 상대를 차단) OR (상대가 나를 차단)"이므로, 호출자가 "나는 상대를 차단한 적
-- 없다"는 사실을 이미 알고 있으면(dm_blocks_select로 본인 차단 목록은 조회 가능),
-- 반환값이 true일 때 남는 경우의 수는 "상대가 나를 차단했다"뿐 — 역산 가능.
--
-- 이는 dm_fix_bidirectional_block.sql 자체가 지키려던 원칙("dm_blocks_select RLS는
-- 그대로 유지 — '누가 나를 차단했는지' 노출 금지 정책 불변")을 정확히 깨뜨린다.
--
-- ── 왜 EXECUTE를 그냥 빼면 안 되는가 ───────────────────────
-- RLS 정책 안에서 함수를 호출할 때도 Postgres는 호출하는 롤(여기서는 authenticated)의
-- EXECUTE 권한을 그대로 검사한다. 정책이라고 예외를 받지 않는다. authenticated에서
-- EXECUTE를 회수하면 이 정책이 걸린 모든 dm_messages INSERT(=메시지 전송 전체)가
-- "permission denied for function is_dm_blocked_between"로 실패한다 — DM 전송
-- 기능 자체가 깨지므로 이 방법은 쓸 수 없다.
--
-- 정책 안에 dm_blocks를 직접 서브쿼리로 인라인하는 것도 안 된다 — 정책은 호출자
-- 권한(authenticated)으로 평가되므로 dm_blocks_select RLS(본인 차단 행만 보임)가
-- 그대로 걸려서, 애초에 이 헬퍼를 만들게 된 원래 비대칭 버그(A→B만 막히고
-- B→A는 안 막힘, dm_fix_bidirectional_block.sql 참고)로 되돌아간다. SECURITY DEFINER
-- 함수는 반드시 필요하다.
--
-- ── 수정 방향 ──────────────────────────────────────────────
-- PostgREST는 기본적으로 public 스키마(및 명시적으로 노출 설정한 스키마)만
-- /rest/v1/rpc/*로 노출한다. private처럼 노출 목록에 없는 스키마의 함수는,
-- RLS 정책 평가(Postgres 엔진 내부에서 직접 호출)에서는 정상 작동하지만
-- REST API로는 아예 보이지 않는다. 이 성질을 이용해 함수 자체는 그대로 두고
-- "어디서 호출 가능한가"만 바꾼다 — 차단 판정 로직 자체는 전혀 변경하지 않는다.
--
-- 1) create schema private — RLS 정책 전용 헬퍼를 모아둘 내부 전용 스키마
-- 2) is_dm_blocked_between을 private.is_dm_blocked_between으로 이동
--    (양방향 체크 로직 + "호출자가 그 쌍에 포함될 때만" 가드 그대로 유지 —
--     RPC로 직접 호출 불가능해진 뒤에도 이중 방어로 남겨둔다)
-- 3) dm_messages_insert 정책이 private.is_dm_blocked_between을 참조하도록 재생성
-- 4) private 스키마/함수에 authenticated에게만 최소 권한 부여 (anon 제외)
-- 5) public.is_dm_blocked_between은 정책 전환 완료 후 완전히 drop
-- ============================================


-- ============================================
-- 1. private 스키마 — RLS 정책 전용 SECURITY DEFINER 헬퍼 보관용
--    절대로 Supabase Dashboard의 Exposed schemas에 추가하지 않는다.
--    (이 파일 상단 "실행 전 필수 확인 사항" 참고)
-- ============================================
create schema if not exists private;
comment on schema private is
  'PostgREST(Data API)에 절대 노출하지 않는 내부 전용 스키마. RLS 정책에서만 쓰는 SECURITY DEFINER 헬퍼 함수를 둔다. Dashboard Exposed schemas에 추가 금지.';

-- 새로 만든 스키마라 기본적으로 PUBLIC에 권한이 열려있지 않지만, 명시적으로
-- 한 번 더 잠가서 이후 이 스키마에 뭘 추가하든 기본값이 "닫힘"임을 보장한다.
revoke all on schema private from public;


-- ============================================
-- 2. private.is_dm_blocked_between — 기존 public.is_dm_blocked_between과
--    내부 로직 완전히 동일 (양방향 체크 + 당사자 전용 가드)
-- ============================================
create or replace function private.is_dm_blocked_between(p_user_1 uuid, p_user_2 uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.dm_blocks
    where auth.uid() in (p_user_1, p_user_2)   -- 호출자 본인이 그 쌍에 포함될 때만 답변 (임의 쌍 탐색 방지)
      and (
        (blocker_id = p_user_1 and blocked_id = p_user_2)
        or
        (blocker_id = p_user_2 and blocked_id = p_user_1)
      )
  );
$$;

comment on function private.is_dm_blocked_between(uuid, uuid) is
  'dm_messages_insert RLS 전용 헬퍼. private 스키마에 있어 PostgREST가 /rest/v1/rpc/*로 노출하지 않으므로
   클라이언트가 직접 호출해 "상대가 나를 차단했는지" 역산할 수 없다. SECURITY DEFINER로 dm_blocks_select
   RLS를 우회해 양방향 차단을 확인하되, 호출자가 그 두 유저 중 하나가 아니면 무조건 false를 반환하는
   가드는 이중 방어로 그대로 유지한다.';

-- authenticated에게만 최소 권한 부여 — anon에는 schema usage/execute 둘 다 주지 않는다.
revoke all on function private.is_dm_blocked_between(uuid, uuid) from public;
grant usage on schema private to authenticated;
grant execute on function private.is_dm_blocked_between(uuid, uuid) to authenticated;


-- ============================================
-- 3. dm_messages_insert 정책 재생성 — private.is_dm_blocked_between 참조로 교체
--    (CREATE OR REPLACE POLICY는 없으므로 DROP 후 CREATE — 재실행해도 안전)
-- ============================================
drop policy if exists dm_messages_insert on public.dm_messages;

create policy dm_messages_insert on public.dm_messages
  for insert
  with check (
    sender_id = auth.uid()
    and public.is_dm_room_member(room_id, auth.uid())
    and not exists (
      select 1 from public.dm_rooms r
      where r.id = room_id
        and private.is_dm_blocked_between(r.user_a_id, r.user_b_id)
    )
  );


-- ============================================
-- 4. 기존 public.is_dm_blocked_between 제거
--    정책 전환이 끝난 뒤에만 drop — 순서를 바꾸면(먼저 drop) 위 3절 정책 재생성 전까지
--    잠깐이라도 dm_messages_insert가 옛 함수를 못 찾아 전송이 막히는 창이 생길 수 있어
--    반드시 "정책부터 새 함수를 가리키게 한 뒤 → 옛 함수 drop" 순서를 지킨다.
-- ============================================
drop function if exists public.is_dm_blocked_between(uuid, uuid);


-- ============================================
-- 참고 (실행 대상 아님 — 검토용 메모)
-- ============================================
-- - dm_blocks_select/insert/delete RLS, dm_rooms_select, dm_messages_select 등
--   차단·조회 관련 다른 정책은 이번 수정에서 전혀 건드리지 않는다 — 차단 여부
--   판정 로직과 기존 대화 조회 가능 여부는 이전과 완전히 동일하게 유지된다.
-- - get_or_create_dm_room RPC의 자체 차단 검사(dm_blocks를 직접 SELECT하는 부분)는
--   이미 SECURITY DEFINER 함수 내부라 RLS를 우회해서 정상 동작하고 있었고, 애초에
--   이번 오라클 문제와 무관하므로 손대지 않는다.
-- - js/chat.js는 이 RPC를 직접 호출하는 코드가 없으므로(에러 발생 시 일반 안내
--   문구만 표시) 프론트 변경 사항 없음.
--
-- ── Rollback ──────────────────────────────────────────────
-- 문제가 생기면 아래 순서로 되돌린다 (정책부터 옛 함수를 가리키게 한 뒤 새 함수/스키마 정리):
--
--   create or replace function public.is_dm_blocked_between(p_user_1 uuid, p_user_2 uuid)
--   returns boolean language sql security definer set search_path = public stable
--   as $$
--     select exists (
--       select 1 from public.dm_blocks
--       where auth.uid() in (p_user_1, p_user_2)
--         and ((blocker_id = p_user_1 and blocked_id = p_user_2)
--              or (blocker_id = p_user_2 and blocked_id = p_user_1))
--     );
--   $$;
--   revoke all on function public.is_dm_blocked_between(uuid, uuid) from public;
--   grant execute on function public.is_dm_blocked_between(uuid, uuid) to authenticated;
--
--   drop policy if exists dm_messages_insert on public.dm_messages;
--   create policy dm_messages_insert on public.dm_messages
--     for insert
--     with check (
--       sender_id = auth.uid()
--       and public.is_dm_room_member(room_id, auth.uid())
--       and not exists (
--         select 1 from public.dm_rooms r
--         where r.id = room_id
--           and public.is_dm_blocked_between(r.user_a_id, r.user_b_id)
--       )
--     );
--
--   drop function if exists private.is_dm_blocked_between(uuid, uuid);
--   -- private 스키마를 다른 용도로도 안 쓰고 있다면 아래로 완전히 정리 가능(선택):
--   -- drop schema if exists private cascade;
