-- ============================================
-- 개인 환경설정 (user_settings) 신규 테이블
-- 작성일: 2026-08-28
-- 수정일: 2026-08-28 (hide_sensitive_content 기본값 true → false로 정책 변경)
--
-- 목적:
--   MY > 설정 페이지에서 쓰는 사용자별 개인 환경설정을 저장.
--   앞으로 설정 항목이 늘어날 때마다 컬럼을 추가하는 공용 테이블로 사용.
--
-- 설계 원칙 (user_profiles/user_equipment와 동일):
--   user_id(auth.uid()) 기준 PK. 쓰기는 본인 행만 허용.
--   user_profiles와 달리 SELECT도 본인만 허용 — 타인이 조회할 필요가 없는
--   개인 설정이므로 공개 SELECT 정책(user_profiles)을 그대로 따르지 않음.
--
-- 첫 설정 항목: hide_sensitive_content
--   true  = 민감한 요소 숨김
--   false = 민감한 요소 표시 (2026-08-28부터 기본값)
--   row가 없는 사용자(기존/신규 전부, 한 번도 설정을 바꾼 적 없는 사용자)는
--   프론트에서 false로 간주한다 — 실제 "기본값" 판단은 js/utils.js의
--   DEFAULT_USER_SETTINGS가 담당하며, 아래 컬럼 DEFAULT는 앱이 값을 명시하지 않고
--   직접 INSERT할 경우를 위한 스키마 차원의 보조 안전장치일 뿐이다.
--   회원가입 트리거로 row를 미리 만들지 않고, 설정을 최초로 바꿀 때 upsert로 생성.
--
--   주의: 이 컬럼 DEFAULT는 새로 INSERT되는 row에만 적용된다. 이미
--   hide_sensitive_content=true로 저장된 기존 row(설정을 이미 만져본 사용자)는
--   이 DEFAULT 변경과 무관하게 그대로 true를 유지한다.
-- ============================================

-- ── 1. 테이블 생성 ────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id                 uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  hide_sensitive_content  boolean     NOT NULL DEFAULT false,
  updated_at              timestamptz NOT NULL DEFAULT now()
);

-- 이미 이 테이블을 DEFAULT true로 생성해 실행한 적이 있다면(2026-08-28 이전),
-- 아래 ALTER를 한 번 실행해 컬럼 DEFAULT만 맞춰준다. 기존 row 값은 바꾸지 않는다.
ALTER TABLE public.user_settings
  ALTER COLUMN hide_sensitive_content SET DEFAULT false;

-- updated_at은 user_equipment 컨벤션과 동일하게 upsert 시 클라이언트가 now()를 직접 넣음
-- (별도 BEFORE UPDATE 트리거 없이 처리 — 이 저장소의 기존 관례)

-- ── 2. RLS 활성화 ─────────────────────────────
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- SELECT: 본인 행만 — 다른 사용자의 설정은 조회할 필요가 없음.
-- 프론트는 항상 현재 로그인 사용자의 설정만 읽어서 본인 화면 렌더링에 사용한다.
DROP POLICY IF EXISTS "user_settings_select_own" ON public.user_settings;
CREATE POLICY "user_settings_select_own"
  ON public.user_settings FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- INSERT: 본인 행만
DROP POLICY IF EXISTS "user_settings_insert_own" ON public.user_settings;
CREATE POLICY "user_settings_insert_own"
  ON public.user_settings FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- UPDATE: 본인 행만
DROP POLICY IF EXISTS "user_settings_update_own" ON public.user_settings;
CREATE POLICY "user_settings_update_own"
  ON public.user_settings FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE: 정책 의도적으로 생성하지 않음 (현재 기능에서 미사용 -> 기본 차단 유지)
