-- =============================================
-- 무료 랜덤 추첨 "최초 추첨" 서버 이전
-- Supabase Dashboard > SQL Editor에서 1회 실행
--
-- 배경:
--   최초 추첨(runRaffle)이 지금까지 클라이언트 JS에서 전부 처리되고 있었음.
--   1) 신청자 조회에 ORDER BY가 없어 순서가 보장되지 않았고
--   2) 당첨자 계산과 DB 반영이 원자적이지 않았으며 (동시 클릭 시 레이스 가능)
--   3) 작성자가 devtools 콘솔에서 adoptions.update()를 직접 호출해
--      당첨자를 임의로 조작할 수 있는 구조였음.
--   리추첨(redraw_adoption_raffle, adoption_redraw_setup.sql)과 동일하게
--   FOR UPDATE 잠금 + 서버 random() 선택 + 같은 트랜잭션 반영으로 이전한다.
--
-- 상태 전이 기준 (redraw_adoption_raffle과 겹치지 않도록 분리):
--   draw_adoption_raffle   : status = '분양중'      (추첨 전)   → '확인 대기중'
--   redraw_adoption_raffle : status = '확인 대기중' (14일 경과) → '확인 대기중' (신규 당첨자)
-- =============================================

CREATE OR REPLACE FUNCTION public.draw_adoption_raffle(p_adoption_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_adoption        record;
  v_caller_uid      uuid := auth.uid();
  v_winner          record;
  v_applicant_count int;
  v_link            text;
  v_loser           record;
BEGIN
  -- 1) 행 잠금 — 동시 호출 방지의 핵심.
  --    두 번째 호출은 여기서 첫 번째 트랜잭션이 끝날 때까지 대기하고,
  --    깨어난 뒤에는 이미 갱신된 최신 row를 보게 되어 아래 4)에서 걸러진다.
  SELECT * INTO v_adoption
    FROM adoptions
   WHERE id = p_adoption_id
   FOR UPDATE;

  IF v_adoption IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '존재하지 않는 분양이에요.');
  END IF;

  -- 2) 작성자 권한 검증
  IF v_adoption.user_id IS DISTINCT FROM v_caller_uid THEN
    RETURN jsonb_build_object('ok', false, 'error', '작성자만 추첨을 진행할 수 있어요.');
  END IF;

  -- 3) 분양 방식 검증 — "무료분양(adoption_type='free') + 랜덤추첨(free_type='random')"이
  --    아니면 무조건 거부. adoption_id만 맞으면 다른 분양 방식(선착순/유료/경매 등)의
  --    id를 넣어 호출해도 여기서 차단된다.
  IF v_adoption.adoption_type IS DISTINCT FROM 'free'
     OR v_adoption.free_type IS DISTINCT FROM 'random' THEN
    RETURN jsonb_build_object('ok', false, 'error', '랜덤 추첨 분양이 아니에요.');
  END IF;

  -- 4) 재추첨 방지 — 이미 당첨자가 정해졌거나 '분양중' 상태가 아니면 거부.
  --    FOR UPDATE 잠금과 결합되어 동시 호출 시에도 당첨자가 덮어써지지 않는다.
  IF v_adoption.winner_name IS NOT NULL
     OR v_adoption.status IS DISTINCT FROM '분양중' THEN
    RETURN jsonb_build_object('ok', false, 'error', '이미 추첨이 진행된 분양이에요.');
  END IF;

  -- 5) 추첨 시각 검증 — raffle_at은 timestamptz(winner_drawn_at과 동일 계열)로,
  --    now()와 직접 비교해도 타임존 문제가 없다.
  --    raffle_at이 NULL인 경우는 기존 클라이언트 로직(adoption-detail.html:647,
  --    `isPast = raffleAt ? now >= raffleAt : false`)과 동일하게 "아직 도달 안 함"으로
  --    취급해 거부한다 (raffle_at 없이는 화면에도 추첨 버튼이 노출되지 않았음).
  IF v_adoption.raffle_at IS NULL OR now() < v_adoption.raffle_at THEN
    RETURN jsonb_build_object('ok', false, 'error', '아직 추첨 시각이 되지 않았어요.');
  END IF;

  SELECT COUNT(*) INTO v_applicant_count
    FROM adoption_applications WHERE adoption_id = p_adoption_id;

  -- 6) 신청자 0명 — 기존 클라이언트 동작과 동일하게 분양을 바로 종료 처리.
  --    업적 카운터(adoption_complete)는 브라우저 전역 함수라 여기서 처리할 수 없으므로
  --    no_applicants 플래그만 반환하고, 클라이언트가 기존과 동일하게 처리한다.
  IF v_applicant_count = 0 THEN
    UPDATE adoptions SET status = '완료' WHERE id = p_adoption_id;
    RETURN jsonb_build_object('ok', true, 'no_applicants', true);
  END IF;

  -- 7) 서버 랜덤 선택 (Postgres random() — 클라이언트 Math.random() 아님)
  SELECT applicant_nickname, applicant_id INTO v_winner
    FROM adoption_applications
   WHERE adoption_id = p_adoption_id
   ORDER BY random()
   LIMIT 1;

  -- 8) 당첨자 선택 + 저장을 같은 트랜잭션에서 처리
  UPDATE adoptions
     SET winner_name     = v_winner.applicant_nickname,
         winner_user_id  = v_winner.applicant_id,
         winner_drawn_at = now(),
         status          = '확인 대기중'
   WHERE id = p_adoption_id;

  v_link := 'adoption-detail.html?id=' || p_adoption_id;

  -- 9) 당첨자 알림
  IF v_winner.applicant_id IS NOT NULL THEN
    PERFORM public.notify_user_by_id(
      v_winner.applicant_id, 'raffle_win',
      '🎲 "' || v_adoption.character_name || '" 랜덤 추첨에 당첨됐어요! 분양자가 확정을 처리할 예정이에요.',
      v_link
    );
  END IF;

  -- 10) 분양자(작성자) 알림
  IF v_adoption.user_id IS NOT NULL THEN
    PERFORM public.notify_user_by_id(
      v_adoption.user_id, 'raffle_done',
      '🎲 "' || v_adoption.character_name || '" 추첨 결과: ' || v_winner.applicant_nickname || '님 당첨!',
      v_link
    );
  END IF;

  -- 11) 낙첨자 알림 — applicant_id(UUID)가 있는 신청자.
  --     기존 클라이언트(runRaffle)와 동일하게 작성자 본인 닉네임은 낙첨 알림에서 제외.
  FOR v_loser IN
    SELECT applicant_id, applicant_nickname
      FROM adoption_applications
     WHERE adoption_id = p_adoption_id
       AND applicant_id IS DISTINCT FROM v_winner.applicant_id
       AND applicant_id IS NOT NULL
       AND applicant_nickname IS DISTINCT FROM v_adoption.author
  LOOP
    PERFORM public.notify_user_by_id(
      v_loser.applicant_id, 'raffle_lose',
      '🎲 참여한 "' || v_adoption.character_name || '" 추첨이 완료됐어요. 이번엔 아쉽지만 다음 기회에!',
      v_link
    );
  END LOOP;

  -- 12) 낙첨자 알림 — applicant_id가 NULL인 구데이터 신청자(0816 INSERT RLS 강화 이전 데이터).
  --     기존 클라이언트 fallback(runRaffle 897~908줄: 닉네임 기반 notifications 직접 INSERT)과
  --     동일하게 처리 — SECURITY DEFINER라 RLS 우회로 직접 INSERT 가능.
  INSERT INTO public.notifications (user_nickname, type, message, link)
  SELECT DISTINCT applicant_nickname, 'raffle_lose',
         '🎲 참여한 "' || v_adoption.character_name || '" 추첨이 완료됐어요. 이번엔 아쉽지만 다음 기회에!',
         v_link
    FROM adoption_applications
   WHERE adoption_id = p_adoption_id
     AND applicant_id IS NULL
     AND applicant_nickname IS DISTINCT FROM v_winner.applicant_nickname
     AND applicant_nickname IS DISTINCT FROM v_adoption.author;

  RETURN jsonb_build_object(
    'ok', true,
    'winner_name', v_winner.applicant_nickname,
    'winner_user_id', v_winner.applicant_id,
    'applicant_count', v_applicant_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.draw_adoption_raffle(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.draw_adoption_raffle(bigint) TO authenticated;
