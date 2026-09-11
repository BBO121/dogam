-- ============================================================
-- characters_name_edit_guard() 트리거 — 종족주에게 owner_custom_name 수정 권한 확장
-- 작성일: 2026-09-12
--
-- 기존(character_owner_custom_name_0912.sql, 실행됨) 정책:
--   name              → 종족주 / admin·staff만
--   owner_custom_name → 현재 소유주 / admin·staff만  (종족주 불가)
--
-- 변경 후:
--   name              → 종족주 / admin·staff만 (그대로)
--   owner_custom_name → 현재 소유주 / 종족주 / admin·staff (종족주 추가 허용)
--
-- 소유권 이전 시 owner_custom_name 자동 NULL 초기화 로직(NEW.owner_user_id 변경 감지)은
-- 그대로 유지 — 이 파일에서 건드리는 부분은 owner_custom_name 컬럼 단위 권한 검사 한 줄뿐.
-- CREATE OR REPLACE라 재실행해도 안전.
-- ============================================================

CREATE OR REPLACE FUNCTION public.characters_name_edit_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role             text := ((auth.jwt() -> 'app_metadata') ->> 'role');
  v_is_privileged    boolean := v_role = ANY (ARRAY['admin', 'staff']);
  v_is_owner         boolean := (auth.uid() IS NOT NULL AND OLD.owner_user_id = auth.uid());
  v_is_species_owner boolean := EXISTS (
    SELECT 1 FROM public.species s
    WHERE s.name = OLD.species_name AND s.owner_user_id = auth.uid()
  );
  v_owner_changed    boolean := NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id;
BEGIN
  -- (a) 소유권이 바뀌는 UPDATE는 owner_custom_name을 같은 문장 안에서 무조건 초기화한다.
  --     호출자가 이 컬럼에 어떤 값을 실어 보냈든 여기서 덮어써 안전하게 정리한다. (변경 없음)
  IF v_owner_changed THEN
    NEW.owner_custom_name := NULL;
  END IF;

  -- admin/staff는 기존과 동일하게 전 컬럼 자유롭게 수정 가능(운영 정책 유지)
  IF v_is_privileged THEN
    RETURN NEW;
  END IF;

  -- (b-1) 등록명(characters.name)은 종족주만 변경 가능 (변경 없음)
  IF NEW.name IS DISTINCT FROM OLD.name AND NOT v_is_species_owner THEN
    RAISE EXCEPTION '등록명은 종족주만 수정할 수 있어요.';
  END IF;

  -- (b-2) 소유주 설정 이름(owner_custom_name)은 현재 소유주 또는 종족주만 변경 가능.
  --       [변경] 기존에는 NOT v_is_owner만 검사했으나, 종족주도 개체 관리자로서
  --       소유주 관련 정보를 수정할 수 있는 기존 정책에 맞춰 v_is_species_owner도 허용.
  --       소유권 이전으로 인한 자동 초기화((a)에서 처리)는 이 검사에서 계속 제외한다 —
  --       그렇지 않으면 이전을 받는 새 소유주가 이전 트랜잭션 자체를 막아버리게 된다.
  IF NOT v_owner_changed
     AND NEW.owner_custom_name IS DISTINCT FROM OLD.owner_custom_name
     AND NOT (v_is_owner OR v_is_species_owner) THEN
    RAISE EXCEPTION '소유주 설정 이름은 현재 소유주 또는 종족주만 수정할 수 있어요.';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.characters_name_edit_guard IS
'characters UPDATE 트리거: (1) owner_user_id가 바뀌는 모든 UPDATE에서 owner_custom_name을 자동 NULL 초기화(원자적, RPC별 개별 수정 불필요) (2) admin/staff를 제외하고 name은 종족주만, owner_custom_name은 현재 소유주 또는 종족주만 바꿀 수 있도록 컬럼 단위로 강제(2026-09-12: 종족주도 owner_custom_name 수정 가능하도록 확장). 기존 characters_update_by_role_or_owner 행 단위 RLS는 그대로 두고 추가 방어선으로 얹은 것 — 정책 재설계 아님.';

-- 트리거 자체(trg_characters_name_edit_guard)는 이미 생성돼 있으므로 재생성 불필요 —
-- CREATE OR REPLACE FUNCTION만으로 트리거가 참조하는 함수 본문이 즉시 갱신된다.
