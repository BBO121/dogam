-- ============================================================
-- 대표 캐릭터 (user_profiles.representative_character_id) 신규 기능
-- 작성일: 2026-08-21
--
-- 목적: 유저가 자신이 소유한 캐릭터 1개를 "대표 캐릭터"로 지정.
--
-- 조사 결과 요약:
--   - characters.id 는 bigint, 소유권은 characters.owner_user_id(uuid)로 판단.
--   - 소유권 이전은 RPC 없이 프론트에서 characters를 직접 UPDATE 한다
--     (character.html confirmTransfer / admin.html confirmAdminTransfer /
--     accept_transfer RPC 등 경로가 여러 개이며 전부 owner_user_id를 직접 바꿈).
--     → "이전 시 대표 캐릭터 자동 해제"를 프론트 코드 수정으로 각 경로마다
--     추가하면 누락 위험이 크므로, characters 테이블에 트리거를 걸어
--     경로에 상관없이 DB 레벨에서 항상 정리되도록 한다.
--   - 캐릭터 삭제는 admin.html deleteChar()가 characters를 직접 DELETE.
--     → FK ON DELETE SET NULL로 선언적으로 처리(트리거 불필요).
--   - 기존 character_representative_step.sql(개체별 대표 이미지 Step)에서
--     이미 "BEFORE 트리거로 참조 무결성 검증" 패턴을 쓰고 있어 동일한 방식을
--     그대로 따른다.
--   - user_profiles RLS 확인 완료(2026-08-21, 뽀 확인): SELECT public read,
--     INSERT/UPDATE 모두 user_id = auth.uid()로 본인 행만 허용. 정상 적용됨.
--     (WITH CHECK까지 user_id = auth.uid()라 애초에 user_id 자체를 다른
--     값으로 바꿔치기하는 것은 RLS 레벨에서 불가능 — old/new 둘 다
--     auth.uid()와 같아야 하므로 old=new만 가능). 아래 검증 트리거는
--     이 RLS와 별개로 "본인 소유가 아닌 캐릭터를 대표로 지정"하는 것 자체를
--     DB 레벨에서 한 번 더 차단하는 방어선이다(RLS가 미래에 바뀌거나
--     관리자/서비스 롤이 직접 쓰는 경로가 생겨도 항상 적용됨).
--
-- [동시성/레이스 컨디션 검토 — 2026-08-21 하드닝]
--   - 문제: "대표 캐릭터로 지정"(check 트리거의 소유권 확인 SELECT)과
--     "그 캐릭터의 소유권 이전"(characters.owner_user_id UPDATE)이
--     동시에 실행되면 TOCTOU(check-then-act) 레이스가 생길 수 있다.
--     일반 SELECT는 락을 잡지 않으므로, 이전 트랜잭션이 아직 커밋되지
--     않은 시점에 옛 소유권 값을 읽어 통과시켜버릴 수 있고, 이후 이전이
--     늦게 커밋되면 "본인 소유가 아닌 캐릭터가 대표로 남는" 상태가
--     생길 수 있다(그 캐릭터가 다시 이전되기 전까지는 아무도 정리하지 않음).
--   - 해결: 소유권 확인 SELECT에 FOR KEY SHARE를 추가해 characters 행을
--     잠근다. 동시에 그 행을 UPDATE하는 트랜잭션(이전)이 있으면 그 트랜잭션이
--     끝날 때까지 대기했다가, 최신 커밋된 값으로 조건을 다시 평가한다
--     (PostgreSQL의 EvalPlanQual 메커니즘 — FOR UPDATE/SHARE 계열의 표준 동작).
--     이는 FK 제약 자체가 참조 무결성 검사 시 자동으로 거는 락과 동일한
--     원리이며, 이 파일의 ON DELETE SET NULL이 "대표 캐릭터로 지정 중인
--     캐릭터가 동시에 삭제되는" 레이스를 이미 이 방식으로 안전하게 처리하고
--     있는 것과 같은 선상이다.
--   - 트레이드오프: 정말 같은 캐릭터를 같은 순간에 "대표로 지정"과 "이전"이
--     동시에 건드리면, 이론상 PostgreSQL 데드락 감지기가 둘 중 하나를
--     "deadlock detected" 에러로 중단시킬 수 있다(대표 지정 UPDATE가
--     user_profiles 행을 먼저 잠근 뒤 characters 행 락을 기다리고, 이전
--     UPDATE의 AFTER 트리거가 반대 순서로 같은 두 행의 락을 기다리는
--     교차 대기 상황). 데이터 정합성은 항상 보장되며(한쪽이 안전하게
--     롤백됨), 사용자에게는 실패 메시지가 뜨고 재시도하면 된다 — 이 정도로
--     극히 드문 동시 충돌까지 막으려고 별도의 재시도/어드바이저리 락 로직을
--     추가하는 것은 과설계로 판단해 적용하지 않았다.
--
-- [SECURITY DEFINER 하드닝]
--   - clear_representative_character_if_disqualified()는 다른 유저(이전
--     소유주)의 user_profiles 행을 정리해야 해서 SECURITY DEFINER가 필요함.
--     search_path를 public도 제외한 pg_catalog, pg_temp로 최소화하고 본문의
--     모든 테이블 참조를 public.으로 완전정규화해서, search_path 하이재킹
--     (동일 이름의 악의적 객체를 심어 이 함수가 엉뚱한 것을 참조하게 만드는
--     공격)을 원천 차단했다. PUBLIC 실행 권한도 명시적으로 회수한다
--     (RETURNS trigger 함수는 원래 트리거로만 실행되고 일반 SQL로 직접
--     호출할 수 없어 실질적 영향은 없지만, 방어적으로 회수). 함수가 하는
--     일도 대표 캐릭터 정리 한 가지로 좁게 제한되어 있다.
--   - 같은 이유로 check_representative_character_ownership()도 SECURITY
--     DEFINER는 아니지만(호출자 본인 권한으로 충분 — characters SELECT는
--     public read, user_profiles 쓰기는 이미 RLS가 본인 행으로 제한) 동일하게
--     search_path를 pg_catalog, pg_temp로 최소화하고 PUBLIC 실행 권한을
--     회수했다.
-- ============================================================


-- ── 1. 컬럼 추가 ────────────────────────────────────────────
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS representative_character_id bigint
  REFERENCES public.characters(id)
  ON DELETE SET NULL;

COMMENT ON COLUMN public.user_profiles.representative_character_id IS
'유저가 지정한 대표 캐릭터(characters.id). NULL이면 미설정. 반드시 user_id가 소유한 개체만 가능(트리거로 검증). 캐릭터 삭제 시 자동으로 NULL(FK ON DELETE SET NULL). 소유주가 바뀌면 clear_representative_character_if_disqualified 트리거가 자동으로 NULL 처리.';

CREATE INDEX IF NOT EXISTS idx_user_profiles_representative_character_id
  ON public.user_profiles(representative_character_id);


-- ── 2. 소유권 검증 트리거 (user_profiles) ──────────────────
-- representative_character_id를 쓸 때마다, 그 캐릭터가 실제로
-- 이 프로필의 user_id 소유인지(+ 오프사이트 개체 제외) 검증한다.
-- 클라이언트 코드 경로와 무관하게 항상 적용됨.
-- user_id도 트리거 대상 컬럼에 포함 — 이론상 user_id가 바뀌는 경우에도
-- (현재 RLS상 불가능하지만) 항상 재검증되도록 방어적으로 추가.
-- FOR KEY SHARE로 characters 행을 잠가 동시 소유권 이전과의 TOCTOU
-- 레이스를 막는다(위 헤더 주석 "동시성/레이스 컨디션 검토" 참고).

CREATE OR REPLACE FUNCTION public.check_representative_character_ownership()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_owned boolean;
BEGIN
  IF NEW.representative_character_id IS NOT NULL THEN

    SELECT EXISTS (
      SELECT 1
      FROM public.characters c
      WHERE c.id = NEW.representative_character_id
        AND c.owner_user_id = NEW.user_id
        AND COALESCE(c.owner_is_offsite, false) = false
      FOR KEY SHARE OF c
    ) INTO v_owned;

    IF NOT v_owned THEN
      RAISE EXCEPTION
        '대표 캐릭터는 반드시 본인이 소유한 개체여야 합니다.';
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.check_representative_character_ownership() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_check_representative_character_ownership
ON public.user_profiles;

CREATE TRIGGER trg_check_representative_character_ownership
BEFORE INSERT OR UPDATE OF representative_character_id, user_id
ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.check_representative_character_ownership();


-- ── 3. 소유권 이전/오프사이트 전환 시 자동 해제 트리거 (characters) ──
-- characters.owner_user_id 또는 owner_is_offsite가 바뀔 때,
-- 더 이상 그 유저의 소유가 아니게 된 대표 캐릭터 지정을 정리한다.
-- SECURITY DEFINER: 이전 소유주 본인이 아닌 다른 계정(새 소유주, 관리자)이
-- UPDATE를 실행해도 이전 소유주의 user_profiles 행을 정리할 수 있어야 하므로
-- RLS를 우회할 권한이 필요함.

CREATE OR REPLACE FUNCTION public.clear_representative_character_if_disqualified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  IF NEW.owner_user_id IS NULL OR COALESCE(NEW.owner_is_offsite, false) = true THEN
    -- 더 이상 어떤 유저의 소유도 아니게 됨 → 누구의 대표든 전부 해제
    UPDATE public.user_profiles
       SET representative_character_id = NULL
     WHERE representative_character_id = NEW.id;
  ELSE
    -- 여전히 누군가의 소유지만, 그 사람이 바뀌었을 수 있음
    -- → 새 소유주 본인의 지정이 아니면 해제
    UPDATE public.user_profiles
       SET representative_character_id = NULL
     WHERE representative_character_id = NEW.id
       AND user_id <> NEW.owner_user_id;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.clear_representative_character_if_disqualified() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_clear_representative_character_on_transfer
ON public.characters;

CREATE TRIGGER trg_clear_representative_character_on_transfer
AFTER UPDATE OF owner_user_id, owner_is_offsite
ON public.characters
FOR EACH ROW
WHEN (
  OLD.owner_user_id IS DISTINCT FROM NEW.owner_user_id
  OR OLD.owner_is_offsite IS DISTINCT FROM NEW.owner_is_offsite
)
EXECUTE FUNCTION public.clear_representative_character_if_disqualified();


-- ── 4. 적용 확인 ─────────────────────────────────────────
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_profiles'
  AND column_name = 'representative_character_id';
