-- ============================================
-- dm_fix_last_message_preview.sql — 마지막 메시지 삭제 시 dm_rooms 미리보기 재계산
-- 작성일: 2026-08-12
--
-- ⚠️ 상태: DRAFT — 아직 실행하지 마세요.
--   dm_setup.sql은 이미 운영 DB에 적용된 상태이므로 전체를 재실행하지 않고,
--   이 파일(추가분)만 별도로 검토 후 실행합니다.
--
-- ── 왜 필요한가 (실 SQL 기준 확인 완료) ──────────────────────
-- dm_rooms.last_message_at / last_message_preview는 dm_messages_after_insert 트리거
-- (dm_rooms_touch_on_message, dm_setup.sql 125~153번 줄)로만 갱신됩니다. 이 트리거는
-- AFTER INSERT에만 걸려 있고 UPDATE에는 걸려있지 않습니다.
--
-- 메시지 삭제(10단계에서 추가한 soft delete)는 INSERT가 아니라 UPDATE(deleted_at 세팅)이므로
-- 이 트리거가 아예 발동하지 않습니다. 그 결과, 방의 "마지막 메시지"를 삭제해도
-- dm_rooms.last_message_preview에는 삭제 전 원문이 그대로 남아있게 됩니다.
--
-- 예시: B가 "비밀이에요"를 보내고 그게 마지막 메시지인 상태에서 그 메시지를 삭제하면,
-- 채팅방 안에서는 "삭제된 메시지입니다"로 정상 표시되지만, 최근 채팅 목록에는
-- "비밀이에요"라는 삭제된 원문이 계속 노출됩니다 — 개인정보 관점에서 반드시 막아야 함.
--
-- ── 기존 데이터 영향 ──────────────────────────────────────
-- 이 마이그레이션은 스키마(컬럼)를 바꾸지 않고 함수 1개 + 트리거 1개를 추가하며,
-- 5절의 1회성 백필로 기존 dm_rooms 행도 함께 정리합니다.
-- 과거에 이미 "마지막 메시지가 삭제된" 방이 있었다면, 트리거만으로는 그 값이 다음 메시지가
-- 오가기 전까지 예전 그대로 남아있으므로, 5절 UPDATE 2개(있으면 재계산 / 없으면 null)로
-- 지금 시점 기준 정상 값으로 백필합니다. 정상 방(마지막 메시지가 삭제된 적 없는 방)은
-- 재계산 결과가 현재 값과 같아 실제로는 쓰기가 일어나지 않습니다(자세한 근거는 5절 주석 참고).
--
-- ── 무엇을 추가하는가 ────────────────────────────────────
-- 1) dm_rooms_recalc_on_delete(): dm_messages가 soft delete로 UPDATE될 때, 그 방에서
--    "삭제되지 않은 가장 최근 메시지"를 다시 찾아 dm_rooms.last_message_*를 재계산.
--    남은 메시지가 하나도 없으면 전부 null로 되돌림(대화를 시작해보세요 표시로 자연 복귀).
--    dm_rooms_touch_on_message처럼 SECURITY DEFINER — dm_rooms에는 클라이언트용 UPDATE
--    정책이 없으므로(의도적으로 RPC/트리거로만 갱신) 이 트리거도 동일하게 RLS를 우회해야 함.
-- 2) dm_messages_after_update_recalc 트리거: AFTER UPDATE, deleted_at이 바뀐 경우에만 실행.
--    (실제로는 dm_messages_restrict_update 트리거가 deleted_at 세팅 외의 UPDATE를 이미
--    막고 있어 이 WHEN 조건은 사실상 항상 참이지만, 명시적으로 남겨 의도를 분명히 함)
-- 3) 트리거 생성 앞에 drop trigger if exists 가드 추가 — 함수는 create or replace라 재실행에
--    안전하지만, 트리거는 원래 plain create trigger라 이 파일을 실수로 두 번 실행하면
--    "trigger already exists" 에러가 났음. dm_fix_bidirectional_block.sql이 정책 재생성에
--    쓴 것과 동일한 drop-then-create 패턴을 트리거에도 맞춰 적용.
-- 4) 기존 데이터 1회성 백필 — 이 트리거 적용 이전에 이미 soft delete된 메시지가 있던 방은
--    다음 메시지가 오가기 전까지 last_message_*가 예전 값 그대로 남으므로, 지금 시점 기준으로
--    한 번 정리한다. dm_messages 전체를 반복 스캔하지 않도록 방별 최신 미삭제 메시지 1건만
--    DISTINCT ON으로 뽑아 조인하는 단일 UPDATE(+ 미삭제 메시지가 하나도 없는 방을 위한 UPDATE
--    1개 더)로 처리 — per-room 루프/커서 없음.
-- ============================================


create or replace function public.dm_rooms_recalc_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last record;
begin
  if old.deleted_at is not null or new.deleted_at is null then
    return new;   -- soft delete로의 전환(null → non-null)이 아니면 아무 것도 하지 않음
  end if;

  select id, created_at, message_type, content, reference_type
  into v_last
  from public.dm_messages
  where room_id = new.room_id
    and deleted_at is null
  order by created_at desc, id desc   -- created_at 동률 시에도 항상 동일한 메시지를 고르도록 id를 보조 정렬키로 사용
  limit 1;

  if v_last.id is null then
    -- 방에 삭제되지 않은 메시지가 하나도 안 남음 (전부 삭제됨)
    update public.dm_rooms
    set last_message_at = null,
        last_message_type = null,
        last_message_preview = null
    where id = new.room_id;
  else
    -- "삭제되지 않은 가장 최근 메시지" 기준으로 재계산 — dm_rooms_touch_on_message와 동일한 문구 규칙
    update public.dm_rooms
    set last_message_at = v_last.created_at,
        last_message_type = v_last.message_type,
        last_message_preview = case
          when v_last.message_type = 'text'      then left(v_last.content, 80)
          when v_last.message_type = 'image'     then '[사진]'
          when v_last.message_type = 'reference' then
            case v_last.reference_type
              when 'character' then '[개체를 공유했습니다]'
              when 'species'   then '[종족을 공유했습니다]'
              when 'adoption'  then '[분양글을 공유했습니다]'
            end
          else null
        end
    where id = new.room_id;
  end if;

  return new;
end;
$$;

-- 함수는 create or replace라 재실행 시 그대로 덮어써지지만, 트리거는 그렇지 않으므로
-- 재실행 안전을 위해 먼저 drop if exists로 정리한 뒤 create한다.
drop trigger if exists dm_messages_after_update_recalc on public.dm_messages;

create trigger dm_messages_after_update_recalc
  after update on public.dm_messages
  for each row
  when (old.deleted_at is distinct from new.deleted_at)
  execute function public.dm_rooms_recalc_on_delete();


-- ============================================
-- 5. 기존 데이터 1회성 백필
--
-- dm_rooms_recalc_on_delete()와 동일한 우선순위/문구 규칙을 그대로 재사용한다 — 규칙이
-- 어긋나면 트리거 적용 이후 값과 백필 값이 서로 달라질 수 있으므로 반드시 동일해야 함.
--
-- 정상 방(마지막 메시지가 삭제된 적 없는 방)에 대한 안전성:
--   - "그 방에서 현재 삭제되지 않은 메시지 중 가장 최근 것"을 다시 계산해서, 이미 저장된
--     값과 다를 때만(is distinct from) UPDATE한다. 정상 방은 재계산 결과가 현재 저장값과
--     정확히 같으므로 이 조건에서 걸러져 실제로는 쓰기가 일어나지 않는다(no-op).
--   - dm_messages 테이블 자체는 이 백필에서 전혀 건드리지 않는다 — dm_rooms의 세 컬럼만
--     조건부로 덮어쓸 뿐이라 스키마/제약조건에 영향을 줄 여지가 없다.
--   - 두 UPDATE 모두 여러 번 실행해도 결과가 같은 멱등 연산 — 재실행해도 안전하다.
--
-- 규모/성능: per-room 반복 쿼리(N+1) 없이 set-based로 한 번에 처리하며, 기존
-- dm_messages_room_created_idx (room_id, created_at) 인덱스를 활용할 수 있는 형태
-- (DISTINCT ON (room_id) ... ORDER BY room_id, created_at DESC, id DESC)로 작성했다.
-- 실제 실행계획(인덱스 스캔 vs 시퀀셜 스캔 선택 등)은 데이터 분포에 따라 플래너가 결정한다.
-- ============================================

-- 5-1) 삭제되지 않은 메시지가 남아있는 방 — 그 중 가장 최근 메시지 기준으로 재계산
with latest as (
  select distinct on (m.room_id)
    m.room_id, m.created_at, m.message_type, m.content, m.reference_type
  from public.dm_messages m
  where m.deleted_at is null
  order by m.room_id, m.created_at desc, m.id desc   -- created_at 동률 시에도 항상 동일한 메시지를 고르도록 id를 보조 정렬키로 사용
)
update public.dm_rooms r
set last_message_at      = latest.created_at,
    last_message_type    = latest.message_type,
    last_message_preview = case
      when latest.message_type = 'text'      then left(latest.content, 80)
      when latest.message_type = 'image'     then '[사진]'
      when latest.message_type = 'reference' then
        case latest.reference_type
          when 'character' then '[개체를 공유했습니다]'
          when 'species'   then '[종족을 공유했습니다]'
          when 'adoption'  then '[분양글을 공유했습니다]'
        end
      else null
    end
from latest
where r.id = latest.room_id
  and (
    r.last_message_at      is distinct from latest.created_at
    or r.last_message_type    is distinct from latest.message_type
    or r.last_message_preview is distinct from (case
      when latest.message_type = 'text'      then left(latest.content, 80)
      when latest.message_type = 'image'     then '[사진]'
      when latest.message_type = 'reference' then
        case latest.reference_type
          when 'character' then '[개체를 공유했습니다]'
          when 'species'   then '[종족을 공유했습니다]'
          when 'adoption'  then '[분양글을 공유했습니다]'
        end
      else null
    end)
  );

-- 5-2) 삭제되지 않은 메시지가 하나도 안 남은 방(메시지 없거나 전부 삭제됨) — 세 컬럼 모두 null로
update public.dm_rooms r
set last_message_at      = null,
    last_message_type    = null,
    last_message_preview = null
where not exists (
    select 1 from public.dm_messages m
    where m.room_id = r.id and m.deleted_at is null
  )
  and (
    r.last_message_at is not null
    or r.last_message_type is not null
    or r.last_message_preview is not null
  );


-- ============================================
-- 참고 (실행 대상 아님 — 검토용 메모)
-- ============================================
-- - 삭제된 메시지가 방의 "마지막 메시지가 아니었던" 경우(중간 메시지 삭제)에도 이 트리거는
--   똑같이 실행되지만, 재계산 결과가 기존 last_message_*와 동일하게 나오므로 사실상 no-op입니다.
--   "이 메시지가 마지막이었는지" 미리 판별하는 조건분기를 넣지 않고 항상 재계산하는 쪽을
--   택한 이유는 그게 더 단순하고, 타임스탬프 역전 등 예외 상황에도 항상 정답을 보장하기 때문입니다.
-- - dm_messages_after_insert(기존, INSERT 시 갱신)와 이 트리거(UPDATE 시 갱신)는 서로 다른
--   이벤트에 걸려 있어 충돌하지 않습니다.
-- - 백필(5절) 실행 전, 아래 읽기 전용 쿼리로 실제로 몇 개 방이 바뀔지 미리 확인할 수 있습니다
--   (5-1 UPDATE의 WHERE 조건과 동일한 조건을 SELECT COUNT로 바꾼 것뿐, 데이터 변경 없음):
--
--   with latest as (
--     select distinct on (m.room_id)
--       m.room_id, m.created_at, m.message_type, m.content, m.reference_type
--     from public.dm_messages m
--     where m.deleted_at is null
--     order by m.room_id, m.created_at desc, m.id desc
--   )
--   select count(*) as rooms_to_update
--   from public.dm_rooms r
--   join latest on latest.room_id = r.id
--   where r.last_message_at is distinct from latest.created_at
--      or r.last_message_type is distinct from latest.message_type;
--
--   5-2 대상(메시지가 하나도 안 남은 방인데 last_message_*가 아직 값을 갖고 있는 경우) 개수는:
--
--   select count(*) as rooms_to_null
--   from public.dm_rooms r
--   where not exists (select 1 from public.dm_messages m where m.room_id = r.id and m.deleted_at is null)
--     and (r.last_message_at is not null or r.last_message_type is not null or r.last_message_preview is not null);
--
--   실제 실행 시에는 Supabase SQL Editor가 각 UPDATE문마다 "UPDATE n" 형태로 실제 반영된
--   행 수를 보여주므로, 이 두 COUNT 쿼리 결과와 대조해서 예상과 일치하는지 확인하면 됩니다.
