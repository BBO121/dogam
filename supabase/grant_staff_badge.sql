-- ══════════════════════════════════════════════
--  스태프 뱃지(staff / staff_gen1) 등록 + 대상 7명 부여
--
--  뱃지 진열대(badges + user_badges, profile.html)는 기본적으로
--  미획득 뱃지도 회색으로 "전원"에게 보여주는 구조다.
--  staff / staff_gen1 코드는 profile.html의 HIDDEN_IF_UNEARNED
--  필터로 미획득 유저에게는 진열대에서 아예 숨긴다.
--  (다른 뱃지의 표시 로직은 건드리지 않음)
--
--  대상
--  staff (스태프):      뽀 / 율하 / 모로 / 냐수 / 이상어
--  staff_gen1 (1기 스태프): 아요 / 사월
-- ══════════════════════════════════════════════

-- ════════════════════════════════════════════════════════
-- STEP 1 — badges 테이블에 뱃지 2종 등록 (이미 있으면 건너뜀)
-- ════════════════════════════════════════════════════════
INSERT INTO badges (code, name, description, image_url, is_obtainable)
SELECT * FROM (VALUES
  ('staff',      '스태프',
   E'종족연구소를 위해\n힘내주고 있는 스태프\n자, 일하자!!!!',
   'staff.png', false),
  ('staff_gen1', '1기 스태프',
   E'종족연구소를 위해 힘내준\n우리의 고마운 스태프\n고마워요!',
   'staff.png', false)
) AS v(code, name, description, image_url, is_obtainable)
WHERE NOT EXISTS (SELECT 1 FROM badges b WHERE b.code = v.code);


-- ════════════════════════════════════════════════════════
-- STEP 2 — 대상 7명에게 부여 (이미 부여됐으면 건너뜀)
-- ════════════════════════════════════════════════════════
INSERT INTO user_badges (user_id, badge_code, awarded_at)
SELECT v.user_id, v.badge_code, NOW()
FROM (VALUES
  ('8f48ba1f-21f5-4c07-9ad5-f5ef3fc5bf12'::uuid, 'staff'),      -- 뽀
  ('63bdb2b5-99e9-430d-baaa-33857e384b14'::uuid, 'staff'),      -- 율하
  ('3eada7b5-a318-4b1b-b638-36491b023d0a'::uuid, 'staff'),      -- 모로
  ('b37d5ad3-af32-4054-8c51-ec0284e0375b'::uuid, 'staff'),      -- 냐수
  ('ed306925-e0e5-44a4-848b-6d27468d598f'::uuid, 'staff'),      -- 이상어
  ('e0fee7ef-2316-43f9-b498-ed06d9809791'::uuid, 'staff_gen1'), -- 아요
  ('5b31c7c2-575d-46a9-803b-937898e4e081'::uuid, 'staff_gen1')  -- 사월
) AS v(user_id, badge_code)
WHERE NOT EXISTS (
  SELECT 1 FROM user_badges ub
  WHERE ub.user_id = v.user_id AND ub.badge_code = v.badge_code
);


-- ════════════════════════════════════════════════════════
-- STEP 3 — 결과 확인 (7행 모두 나와야 함)
-- ════════════════════════════════════════════════════════
SELECT
  ub.user_id,
  au.raw_user_meta_data->>'nickname' AS nickname,
  ub.badge_code,
  ub.awarded_at
FROM user_badges ub
JOIN auth.users au ON au.id = ub.user_id
WHERE ub.badge_code IN ('staff', 'staff_gen1')
ORDER BY ub.badge_code, ub.awarded_at;
