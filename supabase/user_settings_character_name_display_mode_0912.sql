-- ============================================================
-- user_settings에 개체명 표시 설정 컬럼 추가
-- 작성일: 2026-09-12
--
-- 목적: MY > 내 캐릭터 목록(pages/my-characters.html)에서 카드에 등록명
-- (characters.name) / 소유주 설정 개체명(characters.owner_custom_name) 중
-- 무엇을 우선 표시할지 사용자가 선택 → 계정에 저장해 다음 접속에도 유지.
--
-- 기존 user_settings 테이블(user_settings_setup.sql)의 구조/RLS/UPSERT 관례를
-- 그대로 따른다 — 새 테이블 생성 없음, 컬럼만 추가.
-- ============================================================

-- ── 1. 컬럼 추가 ────────────────────────────────
ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS character_name_display_mode text NOT NULL DEFAULT 'registered';

-- ── 2. 허용값 제약 (registered | owner) ─────────
-- ADD CONSTRAINT IF NOT EXISTS 문법이 없어 DROP-then-ADD로 재실행해도 안전하게 구성
ALTER TABLE public.user_settings
  DROP CONSTRAINT IF EXISTS user_settings_character_name_display_mode_check;
ALTER TABLE public.user_settings
  ADD CONSTRAINT user_settings_character_name_display_mode_check
  CHECK (character_name_display_mode IN ('registered', 'owner'));

COMMENT ON COLUMN public.user_settings.character_name_display_mode IS
'내 캐릭터 목록에서 우선 표시할 이름. registered = 등록명(characters.name, 기본값), owner = 소유주 설정 개체명(characters.owner_custom_name, 없으면 프론트에서 등록명으로 폴백 표시). row가 없는 사용자는 프론트 DEFAULT_USER_SETTINGS(js/utils.js)가 registered로 간주한다.';

-- RLS/INSERT/UPDATE/SELECT 정책은 user_settings_setup.sql의 기존 정책(본인 행만)을
-- 그대로 재사용 — 이 파일에서 별도 정책 추가 없음.
