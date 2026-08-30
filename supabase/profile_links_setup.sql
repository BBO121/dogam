-- ============================================
-- 프로필 외부 계정/링크 연동 (profile_links) 신규 테이블
-- 작성일: 2026-08-30
--
-- 목적:
--   사용자가 프로필에 X(Twitter), Toyhouse, 기타 외부 링크를 등록/표시할 수 있게 한다.
--   같은 플랫폼의 계정을 여러 개 등록할 수 있어야 하고, 앞으로 플랫폼이 늘어날 수 있으므로
--   user_profiles 에 twitter_url 같은 컬럼을 직접 추가하지 않고 별도 테이블(1:N)로 둔다.
--
-- 설계 원칙 (user_profiles 와 동일):
--   - user_id(auth.uid()) 기준. 쓰기는 본인 행만 허용.
--   - SELECT 는 공개 — 프로필은 로그인 사용자 누구나 열람하므로 링크도 공개로 읽는다
--     (user_profiles 의 "SELECT public read" 정책과 동일한 취급).
--   - updated_at 은 이 저장소 관례대로 클라이언트가 upsert/update 시 now() 를 직접 넣는다
--     (별도 BEFORE UPDATE 트리거를 만들지 않음 — user_settings_setup.sql 참고).
--
-- 저장 형식:
--   - platform : 'twitter' | 'toyhouse' | 'youtube'
--              | 'naver_blog' | 'naver_cafe' | 'band'
--              | 'discord' | 'kakaotalk' | 'crepe' | 'other'
--   - label    : 화면에 표시할 이름 (X/Toyhouse 는 계정명, 기타는 사용자가 정한 표시명)
--   - url      : 최종 이동 가능한 URL. 반드시 http:// 또는 https:// 로 시작.
--                javascript:, data: 등 위험 스킴은 CHECK 제약으로 차단.
--                단 Discord(platform='discord')는 공개 프로필 URL이 없어 url = NULL 로 저장한다
--                (칩 클릭 시 사용자명 복사, 링크 이동 없음). 그 외 플랫폼은 url NOT NULL.
--   프론트(pages/profile.html)는 X/Toyhouse 에 대해 계정명만 입력받은 경우
--   저장 직전에 https://x.com/{handle} · https://toyhou.se/{handle} 형태로 정규화한 뒤 저장한다.
--
-- 등록 개수 제한(최대 10개)은 우선 프론트에서만 강제한다. DB CHECK 로는 행 개수를 막을 수
-- 없으므로, 서버 차원 강제가 필요해지면 추후 트리거 추가를 검토한다.
-- ============================================

-- ── 1. 테이블 생성 ────────────────────────────
CREATE TABLE IF NOT EXISTS public.profile_links (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform    text        NOT NULL,
  label       text        NOT NULL,
  url         text,        -- Discord 는 NULL. 그 외 플랫폼은 아래 CHECK 로 NOT NULL 강제.
  sort_order  integer     NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.profile_links IS
'프로필에 표시되는 외부 계정/링크 (X, Toyhouse, 기타). user_id 당 여러 행 허용. SELECT 공개, 쓰기는 본인만.';

-- 기존 테이블(url NOT NULL 로 생성됨)에 대해 NULL 허용으로 완화 — Discord 지원.
-- 이미 NULL 허용 상태면 아무 일도 하지 않는다(재실행 안전).
ALTER TABLE public.profile_links
  ALTER COLUMN url DROP NOT NULL;

-- platform 값 제한
ALTER TABLE public.profile_links
  DROP CONSTRAINT IF EXISTS profile_links_platform_check;
ALTER TABLE public.profile_links
  ADD CONSTRAINT profile_links_platform_check
  CHECK (platform IN ('twitter', 'toyhouse', 'youtube', 'naver_blog', 'naver_cafe', 'band', 'discord', 'kakaotalk', 'crepe', 'other'));

-- URL 스킴 제한 — http/https 만. javascript:, data:, vbscript: 등 차단.
-- 선행 공백/제어문자 우회를 막기 위해 문자열이 정확히 http:// 또는 https:// 로 시작해야 한다.
-- url IS NULL 은 허용 (Discord).
ALTER TABLE public.profile_links
  DROP CONSTRAINT IF EXISTS profile_links_url_scheme_check;
ALTER TABLE public.profile_links
  ADD CONSTRAINT profile_links_url_scheme_check
  CHECK (url IS NULL OR url ~ '^https?://[^[:space:]]+$');

-- Discord 외 플랫폼은 url 필수. (Discord 는 공개 프로필 URL이 없어 NULL)
ALTER TABLE public.profile_links
  DROP CONSTRAINT IF EXISTS profile_links_url_required_check;
ALTER TABLE public.profile_links
  ADD CONSTRAINT profile_links_url_required_check
  CHECK (platform = 'discord' OR url IS NOT NULL);

-- label/url 길이 방어 (과도한 입력 차단). url IS NULL 은 허용.
ALTER TABLE public.profile_links
  DROP CONSTRAINT IF EXISTS profile_links_len_check;
ALTER TABLE public.profile_links
  ADD CONSTRAINT profile_links_len_check
  CHECK (
    char_length(label) BETWEEN 1 AND 100
    AND (url IS NULL OR char_length(url) BETWEEN 1 AND 500)
  );

-- 조회 인덱스 — 프로필 1명분을 sort_order 순으로 가져오는 패턴
CREATE INDEX IF NOT EXISTS profile_links_user_id_sort_idx
  ON public.profile_links (user_id, sort_order, created_at);


-- ── 2. RLS ───────────────────────────────────
ALTER TABLE public.profile_links ENABLE ROW LEVEL SECURITY;

-- SELECT: 공개 프로필 링크 — 누구나 읽기 가능 (user_profiles 와 동일)
DROP POLICY IF EXISTS "profile_links_select_all" ON public.profile_links;
CREATE POLICY "profile_links_select_all"
  ON public.profile_links FOR SELECT
  USING (true);

-- INSERT: 본인 행만 (다른 user_id 로 생성 불가)
DROP POLICY IF EXISTS "profile_links_insert_own" ON public.profile_links;
CREATE POLICY "profile_links_insert_own"
  ON public.profile_links FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- UPDATE: 본인 행만
DROP POLICY IF EXISTS "profile_links_update_own" ON public.profile_links;
CREATE POLICY "profile_links_update_own"
  ON public.profile_links FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE: 본인 행만
DROP POLICY IF EXISTS "profile_links_delete_own" ON public.profile_links;
CREATE POLICY "profile_links_delete_own"
  ON public.profile_links FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);


-- ── 3. 권한 ──────────────────────────────────
GRANT SELECT ON public.profile_links TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.profile_links TO authenticated;
