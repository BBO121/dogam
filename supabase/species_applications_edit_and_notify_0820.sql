-- ============================================================
-- [FEATURE] species_applications 신청자 수정 허용 + "미확인 변경" 알림 기준
-- 작성일: 2026-08-20
--
-- 배경 (뽀 요청):
--   - 현재는 신청자가 신청서를 제출한 뒤 수정할 방법이 프론트에 전혀 없음
--     (species-apply-write.html은 INSERT만 지원, 수정 폼/버튼 없음).
--   - 관리자 메뉴 빨간 알림(js/sidebar.js loadAdminBadges)이 단순히
--     status IN ('접수됨','검토중') 개수만 세고 있어, 관리자가 이미 확인/
--     검토 처리한 신청도 계속 빨간 점이 떠 있음.
--
-- 이번 패치 목표:
--   1) 신청자는 상태가 '접수됨' 또는 '검토중'일 때만 본인 신청을 수정 가능.
--      '승인됨'/'반려됨'(관리자가 최종 처리한 상태)은 수정 불가.
--      신청자가 수정해도 status는 그대로 유지(임의로 되돌리거나 바꾸지 못함).
--   2) "관리자가 아직 확인하지 않은 변화"를 DB 컬럼만으로 판별할 수 있도록
--      applicant_updated_at / admin_checked_at 두 컬럼을 추가.
--      계정/기기에 상관없이 동일하게 동작해야 하므로 localStorage 등 프론트
--      상태가 아니라 DB 컬럼 기준으로 판정한다.
--   3) 신청 관련 RLS를 최소권한 원칙으로 재정비:
--      - 신청자는 본인 신청만 조회/등록/조건부 수정 가능 (status를 직접 바꿀 수 없음)
--      - admin/staff만 상태 변경(승인/검토/반려)·삭제 가능
--      - 권한 판정은 기존과 동일하게 app_metadata.role 기준 (user_metadata 아님)
--
-- 참고: supabase/rls_fix_species_applications_0816.sql(초안, 미실행)이 이미
--       SELECT/INSERT/UPDATE(admin전용)/DELETE(admin전용) 정책 초안을 만들어
--       두었으나 아직 실행되지 않은 것으로 보임. 이 파일이 해당 초안을
--       완전히 대체한다 (아래에서 기존 정책을 이름과 무관하게 전부 지우고
--       다시 만들기 때문에, 0816 파일이 이미 실행되었든 안 되었든 안전하게
--       한 번 더 실행 가능 = idempotent).
--
-- 실행 후 프론트에서 반드시 같이 반영해야 하는 부분(별도 커밋에서 처리):
--   - species-apply-write.html: ?id= 파라미터로 수정 모드 지원 (UPDATE 호출)
--   - species-apply-detail.html: 신청자 소유 + 상태 접수됨/검토중일 때 "수정" 버튼 노출,
--     관리자가 상세를 열람하면 admin_checked_at을 now()로 갱신
--   - species-apply.html: 관리자 화면에 상태 탭(신청/검토중/승인완료(+전체)) 추가
--   - js/sidebar.js: 뱃지 카운트를 "status만" 보지 않고
--     "admin_checked_at IS NULL OR applicant_updated_at > admin_checked_at" 조건 추가
-- ============================================================


-- ---------- 0. 컬럼 추가 ----------
-- admin_checked_at: 관리자가 이 신청의 "현재 내용"을 마지막으로 확인한 시각.
--   NULL이면 관리자가 한 번도 확인한 적 없다는 뜻(신규 신청 포함).
-- applicant_updated_at: 신청자가 신청 내용을 마지막으로 수정/제출한 시각.
--   기본값은 created_at과 동일하게 시작한다.
ALTER TABLE public.species_applications
  ADD COLUMN IF NOT EXISTS applicant_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS admin_checked_at timestamptz;

-- 기존 행 백필: applicant_updated_at은 최초 제출 시각(created_at)으로 채운다
-- (ALTER ... DEFAULT now()로 채우면 모든 기존 행이 "지금 막 수정됨"으로
--  보이게 되어 부정확하므로, 반드시 created_at으로 먼저 백필한 뒤 DEFAULT를 건다).
UPDATE public.species_applications
SET applicant_updated_at = created_at
WHERE applicant_updated_at IS NULL;

ALTER TABLE public.species_applications
  ALTER COLUMN applicant_updated_at SET DEFAULT now(),
  ALTER COLUMN applicant_updated_at SET NOT NULL;

-- 기존 행 중 이미 관리자가 답변/처리한 흔적(answer IS NOT NULL)이 있는 신청은
-- "관리자가 이미 확인했던 상태"이므로 admin_checked_at을 answered_at(없으면 created_at)
-- 으로 백필한다. 그래야 이번 패치 적용 직후 이미 검토중/승인/반려 처리된 옛 신청들이
-- 전부 "미확인"으로 잘못 표시되어 뱃지 숫자가 갑자기 튀는 일이 없다.
-- (answer가 없는 '접수됨' 신청은 admin_checked_at을 NULL로 남겨 정상적으로 "미확인" 처리)
UPDATE public.species_applications
SET admin_checked_at = COALESCE(answered_at, created_at)
WHERE answer IS NOT NULL
  AND admin_checked_at IS NULL;


-- ---------- 1. 신청자 수정 시 필드 잠금 트리거 ----------
-- 목적: RLS WITH CHECK만으로는 "status/answer/admin_checked_at 등은 그대로 두고
-- 신청 내용(species_name/image_url/link)만 바꾸게" 같은 컬럼 단위 보호가 번거로우므로,
-- 트리거로 이중 방어한다.
--   - 호출자가 admin/staff가 아니면(=신청자 본인 수정):
--       status/answer/answered_by/answered_at/admin_checked_at/user_id/created_at을
--       강제로 원래 값(OLD)으로 되돌리고, applicant_updated_at만 now()로 갱신한다.
--       즉 신청자가 API를 직접 호출해도 status를 '승인됨' 등으로 바꿔치기할 수 없다.
--   - admin/staff가 수정하는 경우는 기존처럼 그대로 둔다(변경 없음).
CREATE OR REPLACE FUNCTION public.species_applications_lock_applicant_edit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_role text := (auth.jwt() -> 'app_metadata' ->> 'role');
BEGIN
  IF v_role NOT IN ('admin', 'staff') THEN
    NEW.user_id            := OLD.user_id;
    NEW.created_at          := OLD.created_at;
    NEW.status              := OLD.status;
    NEW.answer               := OLD.answer;
    NEW.answered_by         := OLD.answered_by;
    NEW.answered_at         := OLD.answered_at;
    NEW.admin_checked_at    := OLD.admin_checked_at;
    NEW.applicant_updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_species_applications_lock_applicant_edit
ON public.species_applications;

CREATE TRIGGER trg_species_applications_lock_applicant_edit
BEFORE UPDATE ON public.species_applications
FOR EACH ROW
EXECUTE FUNCTION public.species_applications_lock_applicant_edit();


-- ---------- 2. RLS 재정비 ----------
ALTER TABLE public.species_applications ENABLE ROW LEVEL SECURITY;

-- 기존 정책 전체 동적 제거 (정책명을 몰라도, 0816 초안이 실행됐든 안 됐든 안전)
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'species_applications'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.species_applications', pol.policyname);
  END LOOP;
END $$;

-- 조회: 본인 신청 + admin/staff는 전체
CREATE POLICY "species_applications_select_own_or_staff"
ON public.species_applications
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff')
);

-- 등록: 본인 명의로만, status는 반드시 '접수됨'으로 시작
-- (신청 즉시 '승인됨' 등으로 끼워넣는 것 방지)
CREATE POLICY "species_applications_insert_own"
ON public.species_applications
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND status = '접수됨'
);

-- 수정(신청자 본인): 상태가 '접수됨' 또는 '검토중'일 때만, 본인 신청만.
-- 실제로 status/answer 등을 못 바꾸게 막는 것은 위 트리거가 담당하고,
-- 여기서는 "언제(어떤 상태에서) 수정 시도를 허용할지"만 결정한다.
CREATE POLICY "species_applications_update_own_editable"
ON public.species_applications
FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid()
  AND status IN ('접수됨', '검토중')
)
WITH CHECK (
  user_id = auth.uid()
  AND status IN ('접수됨', '검토중')
);

-- 수정(admin/staff): 상태 변경/답변 등 기존과 동일하게 전체 허용
CREATE POLICY "species_applications_update_staff"
ON public.species_applications
FOR UPDATE
TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff'))
WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff'));

-- 삭제: admin/staff만 (기존 0816 초안과 동일하게 유지)
-- 주의: species-apply-detail.html의 "삭제" 버튼은 현재 신청자 본인에게도
-- (답변이 없을 때) 노출되지만, 이 정책 적용 후에는 신청자 본인의 삭제 요청은
-- RLS에서 거부된다. 이번 작업 범위는 "수정"이라 버튼 노출 로직은 건드리지
-- 않았으니, 필요하면 별도로 안내드릴게요.
CREATE POLICY "species_applications_delete_staff"
ON public.species_applications
FOR DELETE
TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'staff'));

-- anon 정책 없음 = anon 접근 완전 차단 (기존과 동일, 의도된 동작)


-- ---------- 3. 적용 확인용 조회 (선택 실행) ----------
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'species_applications'
-- ORDER BY ordinal_position;
--
-- SELECT policyname, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public' AND tablename = 'species_applications'
-- ORDER BY policyname;
