-- ============================================
-- dm_setup.sql — 1:1 실시간 채팅(DM) 시스템 설계안
-- 작성일: 2026-08-11
--
-- ⚠️ 상태: DRAFT — 아직 실행하지 마세요.
--   뽀 검토 후 승인 시에만 Supabase SQL Editor에서 실행합니다.
--
-- 사전 확인 완료 사항 (실 DB REST API 읽기 전용 조회로 확인, 2026-08-11):
--   - 기존 conversations/messages 테이블: 존재하지만 0 rows, 실사용 이력 없음
--     → 이 파일에서 건드리지 않고 그대로 보존 (참고용 프로토타입)
--   - characters.id / species.id / adoptions.id: 전부 정수형 → reference_id는 bigint
--   - 차단(block) 관련 테이블: 전무 확인 (blocked_users/user_blocks/blocks 등 6종 조회, 전부 없음)
--   - public.user_profiles(user_id, nickname, avatar_url, ...): 존재, anon 조회 가능
--     → 대화 상대 닉네임/아바타는 이 테이블을 항상 join해서 표시 (닉네임 값을 메시지/방에 저장하지 않음)
--
-- 확정된 기획 방향:
--   - 사용자 식별: 전부 auth.uid() 기반 user_id (닉네임 저장 안 함)
--   - 1:1 채팅만 지원 (그룹 채팅 없음)
--   - 읽음 처리: dm_room_reads.last_read_at 기준 (메시지별 읽음 표시 없음)
--   - 차단 후에도 기존 대화 내역은 유지, 새 메시지 전송/새 채팅 시작만 금지
--   - 신고 UI는 v1 제외, 구조만 확장 가능하게 열어둠 (실제 테이블은 생성하지 않음, 하단 주석 참고)
--   - 관리자 전체 열람 권한 없음 (RLS에 admin bypass 없음)
--   - unread: 최초 DB 조회 + 이후 Realtime 갱신 (recipient_id 컬럼으로 필터링)
--   - 채팅 이미지 30일 후 Storage 파일만 자동 삭제, 메시지 기록은 유지
-- ============================================


-- ============================================
-- 1. dm_rooms — 1:1 채팅방
-- ============================================
create table public.dm_rooms (
  id                    bigint generated always as identity primary key,
  user_a_id             uuid not null references auth.users(id) on delete cascade,
  user_b_id             uuid not null references auth.users(id) on delete cascade,
  created_at            timestamptz not null default now(),
  last_message_at       timestamptz,
  last_message_type     text,     -- text/image/reference/system — 목록 미리보기용
  last_message_preview  text,     -- text는 본문 요약, 그 외는 "사진을 보냈습니다" 등 고정 문구
  constraint dm_rooms_user_order  check (user_a_id < user_b_id),   -- 항상 작은 uuid를 a에 저장 → 중복 방 생성 자체가 불가능해짐
  constraint dm_rooms_unique_pair unique (user_a_id, user_b_id)
);

comment on table public.dm_rooms is
  '1:1 채팅방. user_a_id/user_b_id는 항상 uuid 크기순 정렬 저장 — 순서 뒤바뀐 중복 방 생성을 원천 차단. 닉네임은 저장하지 않고 user_profiles를 join해서 표시.';

create index dm_rooms_user_b_idx on public.dm_rooms (user_b_id);


-- ============================================
-- 2. dm_room_reads — 유저별 "여기까지 읽음" 커서
-- ============================================
create table public.dm_room_reads (
  room_id      bigint not null references public.dm_rooms(id) on delete cascade,
  user_id      uuid   not null references auth.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

comment on table public.dm_room_reads is
  '메시지별 읽음이 아닌 방 단위 커서. unread count는 이 값보다 최신인 상대 메시지 수로 계산.';


-- ============================================
-- 3. dm_messages — 메시지 본문
-- ============================================
create table public.dm_messages (
  id              bigint generated always as identity primary key,
  room_id         bigint not null references public.dm_rooms(id) on delete cascade,
  sender_id       uuid   not null references auth.users(id) on delete cascade,
  recipient_id    uuid references auth.users(id) on delete cascade,  -- BEFORE INSERT 트리거로 자동 채움. 클라이언트가 값을 보내도 트리거가 무조건 덮어씀 — RLS 판정에는 사용하지 않고 realtime 필터 전용
  message_type    text not null check (message_type in ('text','image','reference','system')),
  content         text,                     -- text 메시지 본문
  reference_type  text check (reference_type in ('character','species','adoption')),
  reference_id    bigint,                   -- characters.id / species.id / adoptions.id 참조
                                             -- 3개 테이블 중 하나를 가리키는 폴리모픽 참조라 실제 FK 제약은 걸지 않음
                                             -- (조회 시 존재하지 않으면 "삭제된 항목입니다" 등으로 화면 처리 권장)
  created_at      timestamptz not null default now(),
  deleted_at      timestamptz,              -- soft delete. 화면에서는 "삭제된 메시지입니다"로 표시
  constraint dm_messages_content_check check (
    message_type <> 'text' or (content is not null and length(btrim(content)) > 0)
  ),
  constraint dm_messages_content_length_check check (
    content is null or char_length(content) <= 2000
  ),
  constraint dm_messages_reference_check check (
    (message_type = 'reference' and reference_type is not null and reference_id is not null)
    or
    (message_type <> 'reference' and reference_type is null and reference_id is null)
  )
);

comment on table public.dm_messages is
  'message_type=text/image/reference/system. reference_type/reference_id는 message_type=reference일 때만 사용 (character/species/adoption 폴리모픽 참조).';

create index dm_messages_room_created_idx      on public.dm_messages (room_id, created_at);
create index dm_messages_recipient_created_idx on public.dm_messages (recipient_id, created_at);


-- recipient_id 자동 채움 트리거
-- SECURITY DEFINER 아님 — sender는 이미 해당 방 참여자이므로 dm_rooms_select 정책으로 조회 가능 (최소 권한 원칙)
create or replace function public.dm_messages_set_recipient()
returns trigger
language plpgsql
as $$
begin
  select case when r.user_a_id = new.sender_id then r.user_b_id else r.user_a_id end
  into new.recipient_id
  from public.dm_rooms r
  where r.id = new.room_id;

  if new.recipient_id is null then
    raise exception '유효하지 않은 채팅방입니다';
  end if;

  return new;
end;
$$;

create trigger dm_messages_before_insert
  before insert on public.dm_messages
  for each row execute function public.dm_messages_set_recipient();


-- 새 메시지가 오면 dm_rooms.last_message_* 갱신 (목록 화면 미리보기용)
create or replace function public.dm_rooms_touch_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.dm_rooms
  set last_message_at      = new.created_at,
      last_message_type    = new.message_type,
      last_message_preview = case
        when new.message_type = 'text'      then left(new.content, 80)
        when new.message_type = 'image'     then '[사진]'
        when new.message_type = 'reference' then
          case new.reference_type
            when 'character' then '[개체를 공유했습니다]'
            when 'species'   then '[종족을 공유했습니다]'
            when 'adoption'  then '[분양글을 공유했습니다]'
          end
        else null   -- system 메시지는 목록 미리보기에서 굳이 노출하지 않음 (필요 시 UI 단계에서 조정)
      end
  where id = new.room_id;
  return new;
end;
$$;

create trigger dm_messages_after_insert
  after insert on public.dm_messages
  for each row execute function public.dm_rooms_touch_on_message();


-- soft delete 전용 잠금 트리거 — UPDATE 정책(dm_messages_soft_delete)이 "본인 메시지"라는 조건만 보므로,
-- 그것만으로는 sender가 content/reference_id 등을 임의로 고쳐쓰는 것까지 막지 못함.
-- 이 트리거로 "deleted_at을 null이 아닌 값으로 세팅하는 것" 외의 모든 변경(복원 포함)을 차단.
create or replace function public.dm_messages_restrict_update()
returns trigger
language plpgsql
as $$
begin
  if new.deleted_at is null then
    raise exception '삭제 해제는 허용되지 않습니다';
  end if;
  if new.content        is distinct from old.content
     or new.message_type   is distinct from old.message_type
     or new.reference_type is distinct from old.reference_type
     or new.reference_id   is distinct from old.reference_id
     or new.room_id        is distinct from old.room_id
     or new.sender_id      is distinct from old.sender_id
     or new.recipient_id   is distinct from old.recipient_id
     or new.created_at     is distinct from old.created_at
  then
    raise exception '삭제 처리 외의 수정은 허용되지 않습니다';
  end if;
  return new;
end;
$$;

create trigger dm_messages_before_update
  before update on public.dm_messages
  for each row execute function public.dm_messages_restrict_update();


-- ============================================
-- 4. dm_message_attachments — 이미지 첨부 (메시지당 여러 장)
-- ============================================
create table public.dm_message_attachments (
  id            bigint generated always as identity primary key,
  message_id    bigint not null references public.dm_messages(id) on delete cascade,
  storage_path  text not null,     -- chat-attachments 버킷 내 경로: {room_id}/{message_id}/{filename}
  width         int,
  height        int,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '30 days'),
  purged_at     timestamptz        -- 실제 Storage 파일 삭제 시각. null = 아직 살아있음
);

comment on table public.dm_message_attachments is
  '30일 만료 배치가 expires_at 지난 행을 찾아 Storage 파일만 삭제하고 purged_at을 기록. 메시지(dm_messages) 자체는 삭제하지 않음.';

create index dm_message_attachments_expiry_idx
  on public.dm_message_attachments (expires_at)
  where purged_at is null;

-- created_at/expires_at 컬럼 DEFAULT는 client가 INSERT 시 값을 명시하면 무시되고 그 값이 그대로 들어감(Postgres 기본 동작).
-- DEFAULT만으로는 "임의 연장 금지"가 보장되지 않으므로, BEFORE INSERT 트리거로 항상 서버 시각 기준 값을 강제 덮어씀.
-- purged_at도 마찬가지로 client insert 시 항상 null로 고정 (만료 배치만 채움).
create or replace function public.dm_attachments_set_expiry()
returns trigger
language plpgsql
as $$
begin
  new.created_at := now();
  new.expires_at := now() + interval '30 days';
  new.purged_at  := null;
  return new;
end;
$$;

create trigger dm_message_attachments_before_insert
  before insert on public.dm_message_attachments
  for each row execute function public.dm_attachments_set_expiry();

-- UPDATE 정책 자체를 정의하지 않았으므로 (아래 7절) 클라이언트는 insert 이후 이 행을 전혀 수정할 수 없음
-- → expires_at 연장 시도 자체가 RLS 기본 차단(정책 없음 = 거부)으로 막힘. 만료 배치는 서비스 롤 키로 RLS 우회.


-- ============================================
-- 5. dm_blocks — 차단
-- ============================================
create table public.dm_blocks (
  blocker_id  uuid not null references auth.users(id) on delete cascade,
  blocked_id  uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint dm_blocks_no_self check (blocker_id <> blocked_id)
);

comment on table public.dm_blocks is
  '차단해도 기존 dm_messages/dm_rooms는 그대로 유지. 새 메시지 전송(dm_messages insert)과 새 방 생성(get_or_create_dm_room)만 막는다.';


-- ============================================
-- (v1 미적용 — 향후 확장용 구조 스케치만, 테이블 생성 안 함)
-- ============================================
-- create table public.dm_reports (
--   id          bigint generated always as identity primary key,
--   message_id  bigint not null references public.dm_messages(id) on delete cascade,
--   reporter_id uuid   not null references auth.users(id),
--   reason      text,
--   status      text default 'pending',
--   created_at  timestamptz not null default now()
-- );
-- message_id 기반으로 이미 참조 구조가 갖춰져 있어 v2에서 테이블만 추가하면 됨


-- ============================================
-- 6. 공통 헬퍼 함수 — 방 참여자 여부
-- ============================================
create or replace function public.is_dm_room_member(p_room_id bigint, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.dm_rooms
    where id = p_room_id
      and (user_a_id = p_user_id or user_b_id = p_user_id)
  );
$$;


-- ============================================
-- 7. RLS 정책
-- ============================================

-- dm_rooms: 조회만 클라이언트에 허용. insert/update는 RPC/트리거(SECURITY DEFINER)로만 수행 → 직접 정책 없음(기본 전체 차단)
alter table public.dm_rooms enable row level security;

create policy dm_rooms_select on public.dm_rooms
  for select
  using (auth.uid() = user_a_id or auth.uid() = user_b_id);


-- dm_room_reads
alter table public.dm_room_reads enable row level security;

create policy dm_room_reads_select on public.dm_room_reads
  for select
  using (public.is_dm_room_member(room_id, auth.uid()));   -- 상대방의 마지막 읽음 시각도 필요 (읽음 표시용)

create policy dm_room_reads_insert on public.dm_room_reads
  for insert
  with check (auth.uid() = user_id and public.is_dm_room_member(room_id, auth.uid()));

create policy dm_room_reads_update on public.dm_room_reads
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- dm_messages
alter table public.dm_messages enable row level security;

create policy dm_messages_select on public.dm_messages
  for select
  using (public.is_dm_room_member(room_id, auth.uid()));

create policy dm_messages_insert on public.dm_messages
  for insert
  with check (
    sender_id = auth.uid()
    and public.is_dm_room_member(room_id, auth.uid())
    and not exists (
      select 1
      from public.dm_rooms r
      where r.id = room_id
        and exists (
          select 1 from public.dm_blocks b
          where (b.blocker_id, b.blocked_id) in (
            (r.user_a_id, r.user_b_id),
            (r.user_b_id, r.user_a_id)
          )
        )
    )
  );

-- soft delete 전용 — 본인 메시지만, sender_id 자체는 변경 불가(policy로 강제는 어려워 애플리케이션에서 deleted_at 외 컬럼은 안 보냄)
create policy dm_messages_soft_delete on public.dm_messages
  for update
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());


-- dm_message_attachments
alter table public.dm_message_attachments enable row level security;

create policy dm_message_attachments_select on public.dm_message_attachments
  for select
  using (
    exists (
      select 1 from public.dm_messages m
      where m.id = message_id and public.is_dm_room_member(m.room_id, auth.uid())
    )
  );

create policy dm_message_attachments_insert on public.dm_message_attachments
  for insert
  with check (
    exists (
      select 1 from public.dm_messages m
      where m.id = message_id
        and m.sender_id = auth.uid()
        and public.is_dm_room_member(m.room_id, auth.uid())
    )
  );


-- dm_blocks — 본인이 차단한 목록만 조회 가능. 상대가 나를 차단했는지는 알 수 없어야 함(간접 노출 방지)
alter table public.dm_blocks enable row level security;

create policy dm_blocks_select on public.dm_blocks
  for select
  using (auth.uid() = blocker_id);

create policy dm_blocks_insert on public.dm_blocks
  for insert
  with check (auth.uid() = blocker_id);

create policy dm_blocks_delete on public.dm_blocks
  for delete
  using (auth.uid() = blocker_id);


-- ============================================
-- 8. RPC — 방 생성/조회 (중복 방지, 차단 검사)
-- ============================================
create or replace function public.get_or_create_dm_room(p_other_user_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me      uuid := auth.uid();
  v_a       uuid;
  v_b       uuid;
  v_room_id bigint;
begin
  if v_me is null then
    raise exception '로그인이 필요합니다';
  end if;
  if p_other_user_id is null or p_other_user_id = v_me then
    raise exception '잘못된 상대입니다';
  end if;

  if exists (
    select 1 from public.dm_blocks
    where (blocker_id = v_me and blocked_id = p_other_user_id)
       or (blocker_id = p_other_user_id and blocked_id = v_me)
  ) then
    raise exception '차단된 상대와는 새 채팅을 시작할 수 없습니다';
  end if;

  v_a := least(v_me, p_other_user_id);
  v_b := greatest(v_me, p_other_user_id);

  insert into public.dm_rooms (user_a_id, user_b_id)
  values (v_a, v_b)
  on conflict (user_a_id, user_b_id) do nothing;

  select id into v_room_id
  from public.dm_rooms
  where user_a_id = v_a and user_b_id = v_b;

  return v_room_id;
end;
$$;

revoke all on function public.get_or_create_dm_room(uuid) from public;
grant execute on function public.get_or_create_dm_room(uuid) to authenticated;


-- ============================================
-- 9. RPC — 읽음 처리
-- ============================================
create or replace function public.mark_dm_room_read(p_room_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_dm_room_member(p_room_id, auth.uid()) then
    raise exception '참여자가 아닙니다';
  end if;

  insert into public.dm_room_reads (room_id, user_id, last_read_at)
  values (p_room_id, auth.uid(), now())
  on conflict (room_id, user_id) do update set last_read_at = excluded.last_read_at;
end;
$$;

revoke all on function public.mark_dm_room_read(bigint) from public;
grant execute on function public.mark_dm_room_read(bigint) to authenticated;


-- ============================================
-- 10. RPC — 헤더 배지용 전체 안읽음 수
-- ============================================
create or replace function public.get_dm_unread_total()
returns bigint
language sql
security definer
set search_path = public
stable
as $$
  select count(*)::bigint
  from public.dm_messages m
  where m.recipient_id = auth.uid()
    and m.deleted_at is null
    and m.created_at > coalesce(
      (select rr.last_read_at from public.dm_room_reads rr
       where rr.room_id = m.room_id and rr.user_id = auth.uid()),
      'epoch'::timestamptz
    );
$$;

revoke all on function public.get_dm_unread_total() from public;
grant execute on function public.get_dm_unread_total() to authenticated;

-- 개별 방의 안읽음 수 (대화방 목록 각 항목에 표시)
create or replace function public.get_dm_room_unread(p_room_id bigint)
returns bigint
language sql
security definer
set search_path = public
stable
as $$
  select count(*)::bigint
  from public.dm_messages m
  where m.room_id = p_room_id
    and m.recipient_id = auth.uid()
    and m.deleted_at is null
    and m.created_at > coalesce(
      (select rr.last_read_at from public.dm_room_reads rr
       where rr.room_id = p_room_id and rr.user_id = auth.uid()),
      'epoch'::timestamptz
    );
$$;

revoke all on function public.get_dm_room_unread(bigint) from public;
grant execute on function public.get_dm_room_unread(bigint) to authenticated;


-- ============================================
-- 11. Storage — chat-attachments 버킷 + 정책
-- ============================================
-- 비공개 버킷: 참여자만 접근 (기존 characters/species 이미지가 쓰는 공용 images 버킷과 분리)
-- image MIME만 허용 + 업로드 용량 제한(8MB, 클라이언트에서 리사이즈/압축 후 업로드 전제)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-attachments', 'chat-attachments', false,
  8388608,  -- 8MB
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public              = excluded.public,
  file_size_limit     = excluded.file_size_limit,
  allowed_mime_types  = excluded.allowed_mime_types;

-- 경로 규칙: {room_id}/{message_id}/{filename}
-- room 참여자인지뿐 아니라, 경로의 message_id가 실제로 그 room에 속한 메시지인지까지 검증.
-- (room_id만 검증하면, 내가 속한 방 A의 폴더 밑에 다른 메시지의 message_id를 끼워 넣는 것까지는 못 막기 때문)
create policy chat_attachments_select on storage.objects
  for select
  using (
    bucket_id = 'chat-attachments'
    and exists (
      select 1 from public.dm_messages m
      where m.id      = ((storage.foldername(name))[2])::bigint
        and m.room_id = ((storage.foldername(name))[1])::bigint
        and public.is_dm_room_member(m.room_id, auth.uid())
    )
  );

-- insert는 한 걸음 더: 그 메시지의 sender가 본인이어야 함 (업로드는 메시지 작성자만)
create policy chat_attachments_insert on storage.objects
  for insert
  with check (
    bucket_id = 'chat-attachments'
    and exists (
      select 1 from public.dm_messages m
      where m.id        = ((storage.foldername(name))[2])::bigint
        and m.room_id   = ((storage.foldername(name))[1])::bigint
        and m.sender_id = auth.uid()
    )
  );

-- 삭제는 30일 만료 배치(서비스 롤 키, RLS 우회)에서만 수행 — 클라이언트용 delete 정책은 만들지 않음
-- 업로드 순서 주의: ① dm_messages insert(message_type='image')로 id 발급 → ② 그 id를 경로에 써서 storage 업로드
--                 → ③ dm_message_attachments insert. 순서를 바꾸면 위 정책에서 message_id를 찾지 못해 전부 막힘.


-- ============================================
-- 12. Realtime publication
-- ============================================
-- postgres_changes 구독(헤더 unread 배지, 대화방 실시간 수신)이 동작하려면
-- 테이블이 supabase_realtime publication에 포함되어 있어야 함 — 기본적으로 자동 포함되지 않음.
--
-- ALTER PUBLICATION ... ADD TABLE은 이미 등록된 테이블에 다시 실행하면 에러가 남
-- ("relation is already member of publication") → pg_publication_tables로 존재 확인 후에만 추가하도록 감싸서 재실행 안전하게 처리.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'dm_messages'
  ) then
    alter publication supabase_realtime add table public.dm_messages;
  end if;
end $$;
-- dm_rooms는 v1 범위(목록 realtime 재정렬)에 필수는 아니라 우선 제외.
-- 필요해지면 동일한 패턴으로 dm_rooms를 추가.


-- ============================================
-- 참고: 클라이언트 조회 패턴 (실행 대상 아님, 설계 검증용 메모)
-- ============================================
-- 대화 목록: dm_rooms (내가 속한 방) + user_profiles (상대 닉네임/아바타 join, user_id로 매칭)
--   select r.*, p.nickname, p.avatar_url
--   from dm_rooms r
--   join user_profiles p
--     on p.user_id = case when r.user_a_id = auth.uid() then r.user_b_id else r.user_a_id end
--   where r.user_a_id = auth.uid() or r.user_b_id = auth.uid()
--   order by r.last_message_at desc nulls last;
--
-- 비공개 버킷 이미지 표시: sb.storage.from('chat-attachments').createSignedUrl(path, 3600) 필요
--   (public 버킷이 아니므로 <img src>에 바로 못 씀 — 채팅 패널 열릴 때 배치로 서명 URL 발급 권장)
--
-- 이미지 30일 만료 배치: supabase/functions/purge-expired-chat-images (별도 Edge Function, 서비스 롤 키)
--   1) dm_message_attachments where expires_at < now() and purged_at is null 조회
--   2) storage.objects에서 해당 storage_path 삭제
--   3) purged_at = now() 로 표시
--   4) pg_cron 또는 Supabase 대시보드 Database > Cron Jobs로 매일 1회 트리거
--   ※ pg_cron 사용 가능 여부는 프로젝트 요금제에 따라 다르므로 사전 확인 필요
