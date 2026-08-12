-- ============================================
-- dm_fix_bidirectional_block.sql — dm_messages_insert 양방향 차단 버그 수정
-- 작성일: 2026-08-11
--
-- ⚠️ 상태: DRAFT — 아직 실행하지 마세요.
--   dm_setup.sql은 이미 운영 DB에 적용된 상태이므로 전체를 재실행하지 않고,
--   이 파일(수정분)만 별도로 검토 후 실행합니다.
--
-- ── 버그 원인 (실 SQL 기준 확인 완료) ──────────────────────────
-- 기존 dm_messages_insert 정책이 dm_blocks를 "직접" SELECT해서 양방향 차단을 검사했는데,
-- dm_blocks_select 정책이 auth.uid() = blocker_id인 행만 보여주므로, 정책 내부 서브쿼리도
-- 호출자(=지금 INSERT하는 사람) 기준으로 그 RLS가 그대로 적용됨.
--
-- 즉 A가 B를 차단(blocker_id=A, blocked_id=B)해도, B가 메시지를 보낼 때는 B 세션
-- 기준으로 dm_blocks를 조회하므로 그 행이 안 보여서(blocker_id≠B) not exists(...)가
-- true가 되어 B→A 전송이 그대로 허용되고 있었음. A→B만 막히고 B→A는 막히지 않는
-- 비대칭 버그.
--
-- 참고: get_or_create_dm_room RPC는 이미 SECURITY DEFINER라 이 문제가 없음(함수 전체가
-- RLS를 우회) — 문제는 SECURITY DEFINER가 될 수 없는 "정책" 안에서 테이블을 직접
-- SELECT한 부분에만 있었음.
--
-- ── 수정 방향 ──────────────────────────────────────────────
-- dm_blocks_select RLS는 그대로 유지한다 ("누가 나를 차단했는지" 노출 금지 정책 불변).
-- 대신 SECURITY DEFINER 헬퍼 함수로 RLS를 우회해 "두 유저 사이에 양방향 차단이
-- 존재하는지"만 boolean으로 확인한다. 임의의 두 유저 쌍을 넣어 차단 관계를 캐낼 수
-- 없도록, 호출자 본인이 그 두 유저 중 하나가 아니면 무조건 false를 반환하도록 방어한다
-- (이 함수는 authenticated에게 EXECUTE가 열려 있어야 RLS 정책 평가 시 호출 가능하므로,
-- 함수 자체의 내부 방어가 유일한 안전장치).
-- ============================================


-- ============================================
-- 1. 헬퍼 함수 — 두 유저 사이에 (양방향) 차단이 존재하는지
-- ============================================
create or replace function public.is_dm_blocked_between(p_user_1 uuid, p_user_2 uuid)
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

comment on function public.is_dm_blocked_between(uuid, uuid) is
  'dm_messages_insert RLS 전용 헬퍼. SECURITY DEFINER로 dm_blocks_select RLS를 우회해 양방향 차단을 확인하되,
   호출자가 그 두 유저 중 하나가 아니면 무조건 false를 반환해 임의 유저 쌍의 차단 관계 탐색은 막는다.';

revoke all on function public.is_dm_blocked_between(uuid, uuid) from public;
grant execute on function public.is_dm_blocked_between(uuid, uuid) to authenticated;


-- ============================================
-- 2. dm_messages_insert 정책 재생성 — dm_blocks 직접 SELECT를 헬퍼 호출로 교체
--    (CREATE OR REPLACE POLICY는 없으므로 DROP 후 CREATE)
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
        and public.is_dm_blocked_between(r.user_a_id, r.user_b_id)
    )
  );


-- ============================================
-- 참고 (실행 대상 아님 — 검토용 메모)
-- ============================================
-- - text/reference/image 메시지 전부 dm_messages에 먼저 insert하는 동일 경로를 거치므로,
--   이 정책 하나만 고치면 세 가지 message_type 모두 동일하게 양방향 차단이 적용된다.
-- - image 메시지는 이 INSERT가 실패하면(client: js/chat.js의 dmSendImages) 이미
--   msgErr 체크 후 즉시 return하도록 짜여 있어, Storage 업로드 단계로는 애초에 진입하지
--   않는다 — 이번 SQL 수정만으로 충분하고 클라이언트 코드 변경은 필요 없다.
-- - dm_rooms/dm_messages의 SELECT 정책, Realtime publication은 이번 수정에서 전혀
--   건드리지 않는다 — 차단 후에도 기존 대화 조회는 그대로 유지된다.
