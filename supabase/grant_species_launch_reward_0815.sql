-- ============================================================
-- 종족 프레임/스티커 발매 제작자 보상 지급
-- 작성일: 2026-08-15
--
-- 구성:
--   STEP 0-A. 닉네임 → user_id 매칭 (읽기 전용, 반드시 먼저 확인)
--   STEP 0-B. item_key(style_key) 존재 여부 검증 (읽기 전용)
--   STEP 1.   아이템 지급 (idempotent, ON CONFLICT DO NOTHING)
--   STEP 2.   재화 지급 — 기록 +50, 열쇠 +1 (idempotent, currency_logs로 중복 방지)
--   STEP 3.   알림 전송 (idempotent, notify_user_by_id 재사용)
--   STEP 4.   최종 결과 리포트 (읽기 전용)
--
-- 기존 구조 재사용:
--   - 아이템 지급: user_items (user_id, item_id) + UNIQUE(user_id,item_id)
--     → grant_ayoh_stickers.sql / bump_ticket_setup.sql의 purchase_item 'unique' 분기와 동일 패턴
--   - 재화 지급: user_wallets UPSERT + currency_logs 기록
--     → bank_setup.sql의 transfer_currency RPC와 동일 패턴
--   - 알림: public.notify_user_by_id(uuid, text, text, text) RPC 그대로 호출
--     (SECURITY DEFINER, notifications 테이블에 INSERT)
--
-- 중요 — frame-sp-Bexolotl / sticker-sp-Bexolotl 대소문자 안내:
--   요청서에는 "frame-sp-Bexolotl"(대문자 B)로 적혀 있으나, 2026-08-15에
--   해당 아이템을 등록한 supabase/shop_species_5set_add_0815.sql 기준
--   실제 style_key는 소문자 'frame-sp-bexolotl' / 'sticker-sp-bexolotl'로
--   생성했습니다(이미지 파일명 frame_sp_Bexolotl.png는 대문자, CSS class와
--   style_key는 소문자 — 다른 종족 프레임과 동일한 명명 규칙). STEP 0-B에서
--   두 표기를 모두 조회해 실제 값을 보여주며, 같은 항목(비홀로틀)이라는
--   확신 하에 STEP 1의 냐수 지급분만 대소문자 무시(lower 비교)로 매칭합니다.
--   나머지 8개 item_key는 요청서 표기와 완전히 동일해 그대로 사용합니다.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- STEP 0-A — 닉네임 → user_id 매칭 (읽기 전용)
-- match_count가 1이 아닌 행(0 = 못 찾음, 2 이상 = 동명이인)이 있으면
-- STEP 1~3을 실행하기 전에 반드시 확인/보고할 것. 그런 닉네임은
-- 아래 STEP들에서 자동으로 지급 대상에서 제외됩니다(SKIP).
-- ════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS _grant_targets;

CREATE TEMP TABLE _grant_targets AS
WITH input(nickname_key) AS (
  VALUES
    ('이상어 ms1sharklee'),
    ('뽀'),
    ('냐수'),
    ('율하'),
    ('MS'),
    ('슷큐')
),
candidates AS (
  SELECT
    u.id,
    COALESCE(u.raw_user_meta_data->>'display_name', u.raw_user_meta_data->>'nickname') AS nickname,
    COALESCE(NULLIF(btrim(u.raw_user_meta_data->>'login_id'), ''), split_part(u.email, '@', 1)) AS login_id
  FROM auth.users u
  WHERE u.deleted_at IS NULL
),
candidates_norm AS (
  SELECT
    id,
    nickname,
    login_id,
    lower(NORMALIZE(btrim(COALESCE(nickname, '')), NFC))  AS nickname_norm,
    lower(NORMALIZE(btrim(COALESCE(login_id, '')), NFC))  AS login_id_norm
  FROM candidates
),
input_norm AS (
  SELECT nickname_key, lower(NORMALIZE(btrim(nickname_key), NFC)) AS key_norm
  FROM input
),
matches AS (
  SELECT DISTINCT i.nickname_key, c.id AS user_id, c.nickname AS matched_nickname
  FROM input_norm i
  JOIN candidates_norm c
    ON i.key_norm <> ''
   AND (c.nickname_norm = i.key_norm OR c.login_id_norm = i.key_norm)
)
SELECT
  i.nickname_key,
  m.user_id,
  m.matched_nickname,
  COUNT(m.user_id) OVER (PARTITION BY i.nickname_key) AS match_count
FROM input_norm i
LEFT JOIN matches m ON m.nickname_key = i.nickname_key;

-- 확인용 — 6행(또는 동명이인이 있으면 그 이상) 나와야 함.
-- match_count = 1 이 아닌 행은 STEP 1~3에서 자동 SKIP 됨.
SELECT * FROM _grant_targets ORDER BY nickname_key;


-- ════════════════════════════════════════════════════════════
-- STEP 0-B — item_key(style_key) 존재 여부 검증 (읽기 전용)
-- exact_match_item_id가 NULL이면 해당 표기 그대로는 DB에 없다는 뜻.
-- ════════════════════════════════════════════════════════════
SELECT
  req.item_key AS requested_item_key,
  s.id         AS exact_match_item_id,
  s.style_key  AS exact_match_style_key,
  ci.id        AS case_insensitive_item_id,
  ci.style_key AS case_insensitive_style_key,
  ci.name
FROM (VALUES
  ('frame-sp-octomonster'),
  ('sticker-sp-octomonster'),
  ('frame-sp-petitarachne'),
  ('sticker-sp-petitarachne'),
  ('frame-sp-bbogi'),
  ('sticker-sp-bbogi'),
  ('frame-sp-Bexolotl'),
  ('sticker-sp-Bexolotl'),
  ('frame-sp-bubblere'),
  ('sticker-sp-bubblere')
) AS req(item_key)
LEFT JOIN public.shop_items s  ON s.style_key = req.item_key
LEFT JOIN public.shop_items ci ON lower(ci.style_key) = lower(req.item_key)
ORDER BY req.item_key;


-- ════════════════════════════════════════════════════════════
-- STEP 1 — 아이템 지급 (idempotent)
-- match_count = 1인 닉네임에게만 지급. 이미 보유 중이면 ON CONFLICT로 SKIP.
-- 냐수 두 항목만 대소문자 무시(lower) 매칭 — 사유는 상단 안내 참고.
-- ════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS _grant_item_map;

CREATE TEMP TABLE _grant_item_map AS
SELECT * FROM (VALUES
  ('이상어 ms1sharklee', 'frame-sp-octomonster',   false),
  ('이상어 ms1sharklee', 'sticker-sp-octomonster', false),
  ('이상어 ms1sharklee', 'frame-sp-petitarachne',  false),
  ('이상어 ms1sharklee', 'sticker-sp-petitarachne',false),
  ('뽀',                 'frame-sp-bbogi',          false),
  ('뽀',                 'sticker-sp-bbogi',        false),
  ('냐수',                'frame-sp-Bexolotl',       true),
  ('냐수',                'sticker-sp-Bexolotl',     true),
  ('율하',                'frame-sp-bubblere',       false),
  ('율하',                'sticker-sp-bubblere',     false)
) AS v(nickname_key, item_key, case_insensitive);

INSERT INTO public.user_items (user_id, item_id)
SELECT t.user_id, s.id
FROM _grant_item_map m
JOIN _grant_targets t
  ON t.nickname_key = m.nickname_key AND t.match_count = 1
JOIN public.shop_items s
  ON (NOT m.case_insensitive AND s.style_key = m.item_key)
  OR (m.case_insensitive AND lower(s.style_key) = lower(m.item_key))
ON CONFLICT (user_id, item_id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- STEP 2 — 재화 지급: 기록 +50, 열쇠 +1 (idempotent)
-- source='species_launch_reward_0815'로 이미 지급했는지 통화별로 확인 후 지급.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_source   text := 'species_launch_reward_0815';
  v_note     text := '종족 프레임 & 스티커 발매 감사 보상';
  rec        record;
  v_new_rr   integer;
  v_new_keys integer;
BEGIN
  FOR rec IN
    SELECT DISTINCT user_id, nickname_key
    FROM _grant_targets
    WHERE match_count = 1
  LOOP
    -- 연구기록 +50
    IF NOT EXISTS (
      SELECT 1 FROM public.currency_logs
      WHERE user_id = rec.user_id AND source = v_source AND currency = 'research_records'
    ) THEN
      INSERT INTO public.user_wallets (user_id, research_records, keys, updated_at)
      VALUES (rec.user_id, 50, 0, now())
      ON CONFLICT (user_id) DO UPDATE
        SET research_records = public.user_wallets.research_records + 50,
            updated_at       = now()
      RETURNING research_records INTO v_new_rr;

      INSERT INTO public.currency_logs
        (user_id, type, source, currency, amount, balance_after, note)
      VALUES
        (rec.user_id, 'admin_grant', v_source, 'research_records', 50, v_new_rr, v_note);
    END IF;

    -- 열쇠 +1
    IF NOT EXISTS (
      SELECT 1 FROM public.currency_logs
      WHERE user_id = rec.user_id AND source = v_source AND currency = 'keys'
    ) THEN
      INSERT INTO public.user_wallets (user_id, research_records, keys, updated_at)
      VALUES (rec.user_id, 0, 1, now())
      ON CONFLICT (user_id) DO UPDATE
        SET keys       = public.user_wallets.keys + 1,
            updated_at = now()
      RETURNING keys INTO v_new_keys;

      INSERT INTO public.currency_logs
        (user_id, type, source, currency, amount, balance_after, note)
      VALUES
        (rec.user_id, 'admin_grant', v_source, 'keys', 1, v_new_keys, v_note);
    END IF;
  END LOOP;
END $$;


-- ════════════════════════════════════════════════════════════
-- STEP 3 — 알림 전송 (idempotent)
-- 기존 public.notify_user_by_id RPC 재사용. 동일 type+link로 이미 보낸
-- 알림이 있으면 SKIP.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  rec record;
  v_message text := '종족 프레임 & 스티커 발매 감사의 뜻으로 소정의 재화를 지급해드렸습니다! 💌';
BEGIN
  FOR rec IN
    SELECT DISTINCT user_id
    FROM _grant_targets
    WHERE match_count = 1
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = rec.user_id
        AND type = 'species_launch_reward'
        AND link = 'shop.html'
    ) THEN
      PERFORM public.notify_user_by_id(
        p_user_id := rec.user_id,
        p_type    := 'species_launch_reward',
        p_message := v_message,
        p_link    := 'shop.html'
      );
    END IF;
  END LOOP;
END $$;


-- ════════════════════════════════════════════════════════════
-- STEP 4 — 최종 결과 리포트 (읽기 전용)
-- 이 결과를 그대로 캡처/복사해서 알려주시면 최종 보고에 반영합니다.
-- ════════════════════════════════════════════════════════════
SELECT
  t.nickname_key                                   AS 요청_닉네임,
  t.user_id,
  t.match_count,
  CASE
    WHEN t.match_count = 0 THEN '❌ 유저 못찾음'
    WHEN t.match_count > 1 THEN '⚠ 동명이인 — 임의지급 안함'
    ELSE '✅ 매칭됨'
  END                                               AS 매칭상태,
  (
    SELECT string_agg(s.style_key, ', ' ORDER BY s.style_key)
    FROM public.user_items ui
    JOIN public.shop_items s ON s.id = ui.item_id
    WHERE ui.user_id = t.user_id
      AND s.style_key IN (
        'frame-sp-octomonster','sticker-sp-octomonster',
        'frame-sp-petitarachne','sticker-sp-petitarachne',
        'frame-sp-bbogi','sticker-sp-bbogi',
        'frame-sp-bexolotl','sticker-sp-bexolotl',
        'frame-sp-bubblere','sticker-sp-bubblere'
      )
  )                                                 AS 보유중인_대상_아이템,
  EXISTS (
    SELECT 1 FROM public.currency_logs
    WHERE user_id = t.user_id AND source = 'species_launch_reward_0815' AND currency = 'research_records'
  )                                                 AS 기록_50_지급됨,
  EXISTS (
    SELECT 1 FROM public.currency_logs
    WHERE user_id = t.user_id AND source = 'species_launch_reward_0815' AND currency = 'keys'
  )                                                 AS 열쇠_1_지급됨,
  EXISTS (
    SELECT 1 FROM public.notifications
    WHERE user_id = t.user_id AND type = 'species_launch_reward' AND link = 'shop.html'
  )                                                 AS 알림_전송됨
FROM (SELECT DISTINCT nickname_key, user_id, match_count FROM _grant_targets) t
ORDER BY t.nickname_key;
