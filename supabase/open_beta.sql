-- ══════════════════════════════════════════════
--  open_beta 업적: 오픈 베타 참여 기념
--  현재 가입된 전체 유저에게 1회 지급
--  이후 자동 지급 로직 없음 — 이 SQL을 다시 실행하지 않으면 신규 유저는 획득 불가
-- ══════════════════════════════════════════════

INSERT INTO user_achievements (user_id, achievement_code)
SELECT id, 'open_beta'
FROM auth.users
ON CONFLICT (user_id, achievement_code) DO NOTHING;
