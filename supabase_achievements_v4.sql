-- ══════════════════════════════════════════════
--  업적 시스템 v4 — 숨겨진 업적 7개 + get_counter_value RPC
--  Supabase SQL Editor에서 실행하세요.
-- ══════════════════════════════════════════════


-- ── 1. RPC — 카운터 값 조회 ───────────────────

CREATE OR REPLACE FUNCTION get_counter_value(p_counter_key TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid    := auth.uid();
  v_count   integer;
BEGIN
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  SELECT count INTO v_count
  FROM user_achievement_counters
  WHERE user_id    = v_user_id
    AND counter_key = p_counter_key;

  RETURN COALESCE(v_count, 0);
END;
$$;


-- ── 2. 신규 업적 데이터 삽입 ───────────────────

INSERT INTO achievements (code, name, description, is_hidden) VALUES

-- 연구원 업적
('login_no_auth_5',    '문 두드리는 연구원',       '로그아웃 상태로 로그인 페이지를 5번 확인하세요.',                true),
('night_login',        '야근하는 연구원',           '새벽 1시~3시에 로그인하세요.',                                   true),
('dawn_login',         '연구소 야간경비원',         '새벽 3시~5시에 로그인하세요.',                                   true),
('work_overtime_fail', '퇴근 실패',                 '하루에 종족연구소를 10번 이상 방문하세요.',                       true),

-- 탐험 업적
('visit_404_3',        '연구소 벽을 핥아보셨군요',  '404 페이지를 3번 확인하세요.',                                   true),
('odd_search',         '수상한 검색 기록',          '검색 결과가 없는 종족과 개체를 각각 5번씩 검색하세요.',           true),

-- 종족 연구 업적
('species_revisit_10', '관심 감사합니다?',          '다른 연구원의 같은 종족 페이지를 10번 다시 방문하세요.',          true)

ON CONFLICT (code) DO UPDATE SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  is_hidden   = EXCLUDED.is_hidden;
