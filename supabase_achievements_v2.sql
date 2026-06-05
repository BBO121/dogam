-- ══════════════════════════════════════════════
--  업적 데이터 v2 — 33개 전체 업적
--  Supabase SQL Editor에서 실행하세요.
--  (테이블/RLS는 supabase_achievement_setup.sql 기준으로 이미 설정됨)
-- ══════════════════════════════════════════════


-- ── 기존 7개 업적 이름/설명/is_hidden 정확히 갱신 ──

UPDATE achievements SET name = '이곳은 종족연구소입니다!', description = '처음 종족연구소에 로그인하세요.',  is_hidden = false WHERE code = 'first_login';
UPDATE achievements SET name = '연구원 취직!',             description = '첫 종족을 등록하세요.',             is_hidden = false WHERE code = 'first_species';
UPDATE achievements SET name = '생명 탄생!',               description = '첫 개체를 등록하세요.',             is_hidden = false WHERE code = 'first_character';
UPDATE achievements SET name = '넌 내꺼야!',               description = '첫 내 개체를 가지세요.',            is_hidden = false WHERE code = 'first_owned_character';
UPDATE achievements SET name = '새로운 가족을 찾아서',      description = '첫 분양을 등록하세요.',             is_hidden = false WHERE code = 'first_adoption';
UPDATE achievements SET name = '문의 있습니다!',            description = '첫 문의를 작성하세요.',             is_hidden = false WHERE code = 'first_inquiry';
UPDATE achievements SET name = '버그 사냥꾼',              description = '첫 버그 리포트를 작성하세요.',       is_hidden = false WHERE code = 'first_bug_report';


-- ── 신규 26개 업적 추가 ──────────────────────────

INSERT INTO achievements (code, name, description, is_hidden) VALUES

-- 연구원 업적
('profile_setup',     '마이 네임 이즈...',                 '프로필을 설정하세요.',                      false),
('nickname_set',      '그렇게 불러드릴게요!',               '닉네임을 설정하세요.',                      false),
('first_guide',       '연구소 미아방지시스템',               '첫 가이드를 확인하세요.',                   false),
('open_beta',         '개척자',                            '오픈 베타부터 함께해주셔서 감사합니다.',      false),

-- 종족 연구 업적
('species_3',         '연구할 게 많네요!',                  '종족을 3개 등록하세요.',                    false),

-- 개체 연구 업적
('chars_10',          '복작복작 연구실',                    '내 종족의 개체를 총 10마리 등록하세요.',     false),
('chars_30',          '복작복작복작복작 연구실',             '내 종족의 개체를 총 30마리 등록하세요.',     false),
('chars_50',          '슬슬 연구실 이사가야겠는데?',          '내 종족의 개체를 총 50마리 등록하세요.',     false),
('chars_100',         '이 연구소 가지실래요?',               '내 종족의 개체를 총 100마리 등록하세요.',    true),

-- 분양 업적
('adoption_10',       '좋은 주인 찾아요',                   '분양을 10회 완료하세요.',                   false),
('adoption_20',       '다들 어디로 갔을까?',                '분양을 20회 완료하세요.',                   true),
('adoption_30',       '모두가 행복할거에요!',                '분양을 30회 완료하세요.',                   true),

-- 문의 & 버그 업적
('bug_report_3',      '이상한데요?',                        '버그 리포트를 3번 작성하세요.',              false),
('bug_report_10',     'QA팀 입사해주세요',                  '버그 리포트를 10번 작성하세요.',             true),

-- 탐험 업적
('first_update_note', '읽어주셔서 감사합니다',              '처음 업데이트 노트를 확인하세요.',            false),
('first_dev_log',     '이것까지 읽으시다니!!!',              '첫 개발일지를 확인하세요.',                  false),
('first_notice',      '잘했어요!',                          '첫 공지사항을 확인하세요.',                  false),
('notice_5',          '성실한 연구원',                      '공지사항을 총 5개 확인하세요.',              true),
('no_species_search', '길 잃은 연구원',                     '검색 결과가 없는 종족을 조회하세요.',         false),
('no_char_search',    '아무것도 없는데요?',                  '검색 결과가 없는 개체를 조회하세요.',         false),
('first_terms',       '이것까지 확인하시다니!',              '처음 약관을 확인하세요.',                    true),
('terms_5',           '그렇게 궁금하셨나요?',               '약관을 5번 확인하세요.',                     true),
('terms_20',          '...저희 이상한 거 없어요',            '약관을 20번 확인하세요.',                    true),

-- 공오 업적 (전체 숨김 — 하나라도 획득 시 카테고리 공개)
('gong_o_visit_1',   '안녕하세요! 연구소 마스코트 공오에요!', '공오 개체페이지를 확인하세요.',              true),
('gong_o_visit_5',   '또 오셨네요!',                        '공오 개체페이지를 5번 확인하세요.',           true),
('gong_o_visit_20',  '제가 그렇게 궁금해요!?',              '공오 개체페이지를 20번 확인하세요.',          true),
('gong_o_visit_100', '...그만 좀 와!!!!',                   '공오 개체페이지를 100번 확인하세요.',         true)

ON CONFLICT (code) DO UPDATE SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  is_hidden   = EXCLUDED.is_hidden;
