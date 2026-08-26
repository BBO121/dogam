-- ============================================================
-- award_achievement — 업적 달성 + 보상 지급을 단일 트랜잭션으로 통합
-- 작성일: 2026-08-23
--
-- 배경: 기존 흐름(client 측 upsert → achievements SELECT → notification
--       INSERT → grant_achievement_reward RPC, 총 4단계 순차 네트워크
--       왕복)에서 achievements 재조회 단계가 간헐적으로 실패/취소되면
--       user_achievements만 생성되고 보상/알림이 영구 누락되는 버그가
--       확인됨 (리엔 gong_o_visit_20 외 최근 7일 4건).
--       원인 조사: supabase/investigate_gongo_achievement_bug_0823.sql,
--                  supabase/investigate_achievement_reward_gap_7d_0823.sql
--
-- 이 RPC 하나가 대체하는 것:
--   1) user_achievements upsert         (js/achievements.js)
--   2) achievements SELECT              (js/achievements.js)
--   3) 달성 notification INSERT          (js/achievements.js)
--   4) grant_achievement_reward RPC     (supabase/grant_achievement_reward.sql, deprecated)
--
-- 멱등성 보장 방식:
--   user_achievements에 UNIQUE(user_id, achievement_code) 제약이 이미 있고,
--   INSERT ... ON CONFLICT (user_id, achievement_code) DO NOTHING RETURNING id
--   로 "이번 호출이 신규 unlock인지"를 DB 레벨에서 원자적으로 판별한다.
--   동시에 같은 코드로 N번 호출돼도 유니크 인덱스 특성상 단 1건만
--   RETURNING을 받고, 나머지는 v_inserted_id = NULL → 보상/알림 스킵.
--
-- 원자성(롤백) 보장 방식:
--   전체를 하나의 PL/pgSQL 함수(=하나의 트랜잭션)로 실행. 함수 내에서
--   EXCEPTION 절을 사용하지 않으므로, wallet UPDATE/currency_logs INSERT/
--   notifications INSERT 중 어디서든 예외가 나면 user_achievements INSERT를
--   포함해 함수 전체가 자동 롤백된다 (실패를 중간에 삼키지 않음).
--
-- 호출: sb.rpc('award_achievement', { p_code: code })
-- ============================================================

CREATE OR REPLACE FUNCTION public.award_achievement(
  p_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id     uuid := auth.uid();
  v_nickname    text;
  v_ach_name    text;
  v_ach_desc    text;
  v_is_hidden   boolean;
  v_amount      integer;
  v_new_balance integer;
  v_inserted_id integer;
BEGIN

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'NOT_AUTHENTICATED'
    );
  END IF;

  -- 업적 정의 확인 — 존재하지 않는 코드면 아무것도 쓰지 않고 즉시 오류 반환
  SELECT name, description, is_hidden
  INTO   v_ach_name, v_ach_desc, v_is_hidden
  FROM   achievements
  WHERE  code = p_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'UNKNOWN_ACHIEVEMENT'
    );
  END IF;

  -- 신규 달성 여부를 원자적으로 판별 (동시 호출 대비 DB 레벨 멱등성의 핵심)
  INSERT INTO user_achievements (user_id, achievement_code)
  VALUES (v_user_id, p_code)
  ON CONFLICT (user_id, achievement_code) DO NOTHING
  RETURNING id INTO v_inserted_id;

  IF v_inserted_id IS NULL THEN
    -- 이미 달성된 업적: 신규 지급 없음. 에러가 아니라 정상 응답으로 반환
    -- (클라이언트는 newly_unlocked=false면 토스트/보상 처리를 생략하면 됨)
    RETURN jsonb_build_object(
      'success',        true,
      'newly_unlocked', false,
      'name',           v_ach_name,
      'description',    v_ach_desc
    );
  END IF;

  -- 지급액 결정: 숨김 업적 10 / 일반 업적 5
  v_amount := CASE WHEN v_is_hidden THEN 10 ELSE 5 END;

  -- 닉네임 조회 (알림 user_nickname 용 — 없어도 user_id로 알림 전달)
  SELECT COALESCE(
    raw_user_meta_data->>'display_name',
    raw_user_meta_data->>'nickname'
  )
  INTO  v_nickname
  FROM  auth.users
  WHERE id = v_user_id;

  -- 지갑 지급 — user_wallets 행이 없는 유저도 안전하게 처리
  INSERT INTO user_wallets (user_id, research_records, keys, updated_at)
  VALUES (v_user_id, v_amount, 0, now())
  ON CONFLICT (user_id) DO UPDATE
    SET research_records = public.user_wallets.research_records + v_amount,
        updated_at       = now()
  RETURNING research_records INTO v_new_balance;

  -- 거래 로그 기록
  INSERT INTO currency_logs (user_id, type, source, currency, amount, balance_after, note)
  VALUES (
    v_user_id,
    'achievement_reward',
    'achievement',
    'research_records',
    v_amount,
    v_new_balance,
    v_ach_name
  );

  -- 달성 알림
  INSERT INTO notifications (user_id, user_nickname, type, message, link)
  VALUES (
    v_user_id,
    v_nickname,
    'achievement',
    '[' || v_ach_name || '] 업적을 달성했습니다.',
    'achievements.html'
  );

  -- 보상 알림
  INSERT INTO notifications (user_id, user_nickname, type, message, link)
  VALUES (
    v_user_id,
    v_nickname,
    'achievement',
    '업적 보상으로 연구기록 +' || v_amount || '를 획득했습니다!',
    'my-wallet.html'
  );

  RETURN jsonb_build_object(
    'success',        true,
    'newly_unlocked', true,
    'name',           v_ach_name,
    'description',    v_ach_desc,
    'amount',         v_amount,
    'new_balance',    v_new_balance
  );

END;
$$;
