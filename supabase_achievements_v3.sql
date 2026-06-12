-- ══════════════════════════════════════════════
--  업적 시스템 v3 — 2차 확장
--  Supabase SQL Editor에서 실행하세요.
-- ══════════════════════════════════════════════


-- ── 1. 추적 테이블 생성 ─────────────────────────

CREATE TABLE IF NOT EXISTS user_species_views (
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  species_id INT  NOT NULL,
  viewed_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, species_id)
);

CREATE TABLE IF NOT EXISTS user_character_views (
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  character_id INT  NOT NULL,
  viewed_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, character_id)
);


-- ── 2. RLS 설정 ────────────────────────────────

ALTER TABLE user_species_views   ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_character_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_species_views_own"   ON user_species_views;
DROP POLICY IF EXISTS "user_character_views_own" ON user_character_views;

-- 본인 데이터만 읽기/쓰기
CREATE POLICY "user_species_views_own"
  ON user_species_views
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_character_views_own"
  ON user_character_views
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());


-- ── 3. RPC — 종족 고유 조회 추적 ──────────────

CREATE OR REPLACE FUNCTION track_species_view(p_species_id INT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_count   INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  INSERT INTO user_species_views(user_id, species_id)
  VALUES (v_user_id, p_species_id)
  ON CONFLICT DO NOTHING;

  SELECT COUNT(*)::INT INTO v_count
  FROM user_species_views
  WHERE user_id = v_user_id;

  RETURN v_count;
END;
$$;


-- ── 4. RPC — 개체 고유 조회 추적 ──────────────

CREATE OR REPLACE FUNCTION track_character_view(p_character_id INT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_count   INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  INSERT INTO user_character_views(user_id, character_id)
  VALUES (v_user_id, p_character_id)
  ON CONFLICT DO NOTHING;

  SELECT COUNT(*)::INT INTO v_count
  FROM user_character_views
  WHERE user_id = v_user_id;

  RETURN v_count;
END;
$$;


-- ── 5. RPC — 내가 소유한 서로 다른 종족 수 ────

CREATE OR REPLACE FUNCTION get_distinct_owned_species_count()
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(DISTINCT species_name)::INT
  FROM characters
  WHERE owner_user_id    = auth.uid()
    AND owner_is_offsite = false
    AND species_name     IS NOT NULL;
$$;


-- ── 6. 신규 업적 데이터 삽입 ───────────────────

INSERT INTO achievements (code, name, description, is_hidden) VALUES

-- 종족 상세 조회
('species_view_10', '연구소 관광객',          '종족을 10개 둘러보세요.',    false),
('species_view_30', '견학 끝!',               '종족을 30개 확인하세요.',    false),
('species_view_50', '연구소 비밀자료 열람 중', '종족을 50개 확인하세요.',    true),

-- 종족 검색 결과 없음
('species_search_fail_10', '길치 연구원', '검색창에서 존재하지 않는 종족을 10번 검색하세요.', true),

-- 개체 상세 조회
('char_view_20',  '누가 살고 있을까?',      '개체를 20마리 확인하세요.',  false),
('char_view_50',  '관찰은 기본이죠',        '개체를 50마리 확인하세요.',  false),
('char_view_100', '개체 이름 외웠죠 솔직히', '개체를 100마리 확인하세요.', true),

-- 서로 다른 종족 소유
('own_variety_5',  '다 너무 좋아',    '서로 다른 종족의 개체를 5마리 소유하세요.',  false),
('own_variety_10', '편식하지 않아요', '서로 다른 종족의 개체를 10마리 소유하세요.', false),
('own_variety_20', '뭐든 가능합니다', '서로 다른 종족의 개체를 20마리 소유하세요.', true),

-- 내 소유 개체 설명/관계 입력
('char_owner_desc',     '사실 제 아이는요.',    '내 소유 개체의 설명을 입력하세요.',  false),
('char_owner_relation', '저랑 관계 짜실분?',    '내 소유 개체의 관계를 입력하세요.', false),

-- 404 페이지 (커스텀 404 연동 시 활성화)
('visit_404', '여긴 왜 오셨어요?', '존재하지 않는 페이지를 확인하세요.', true)

ON CONFLICT (code) DO UPDATE SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  is_hidden   = EXCLUDED.is_hidden;
