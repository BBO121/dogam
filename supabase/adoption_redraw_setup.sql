-- =============================================
-- 랜덤 추첨 분양 리추첨 기능
-- Supabase Dashboard > SQL Editor에서 1회 실행
-- =============================================

-- 당첨자가 확정된 시각 (최초 추첨 및 리추첨 시마다 갱신 — 14일 경과 판정 기준)
ALTER TABLE public.adoptions
  ADD COLUMN IF NOT EXISTS winner_drawn_at timestamptz;

-- 마이그레이션 이전에 이미 당첨 확인 대기중인 기존 데이터 백필
-- (실제 추첨 시각을 알 수 없어 raffle_at을 근사치로 사용)
UPDATE public.adoptions
SET winner_drawn_at = COALESCE(winner_drawn_at, raffle_at)
WHERE free_type = 'random'
  AND status = '확인 대기중'
  AND winner_drawn_at IS NULL
  AND winner_name IS NOT NULL;

-- =============================================
-- 리추첨 RPC
-- SECURITY DEFINER: 작성자 검증 후 adoptions 갱신 + 알림 발송을 원자 처리
-- 대상: free_type='random' 인 캐릭터/디자인권(slot) 분양 공통
-- 확장 시 참고: 리추첨 이력을 남기려면 여기서 adoption_redraw_history 같은
--              테이블에 (adoption_id, old_winner, new_winner, redrawn_at) INSERT를 추가하면 됨
-- =============================================

CREATE OR REPLACE FUNCTION public.redraw_adoption_raffle(p_adoption_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_adoption        record;
  v_caller_uid      uuid := auth.uid();
  v_old_winner_name text;
  v_old_winner_uid  uuid;
  v_new_winner      record;
  v_link            text;
BEGIN
  SELECT * INTO v_adoption
    FROM adoptions
   WHERE id = p_adoption_id
   FOR UPDATE;

  IF v_adoption IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '존재하지 않는 분양이에요.');
  END IF;

  IF v_adoption.user_id IS DISTINCT FROM v_caller_uid THEN
    RETURN jsonb_build_object('ok', false, 'error', '작성자만 리추첨을 진행할 수 있어요.');
  END IF;

  IF v_adoption.free_type IS DISTINCT FROM 'random' THEN
    RETURN jsonb_build_object('ok', false, 'error', '랜덤 추첨 분양이 아니에요.');
  END IF;

  IF v_adoption.status IS DISTINCT FROM '확인 대기중' THEN
    RETURN jsonb_build_object('ok', false, 'error', '당첨 확인 대기 상태가 아니에요.');
  END IF;

  IF v_adoption.winner_drawn_at IS NULL OR now() - v_adoption.winner_drawn_at < interval '14 days' THEN
    RETURN jsonb_build_object('ok', false, 'error', '추첨 후 14일이 지나야 리추첨할 수 있어요.');
  END IF;

  v_old_winner_name := v_adoption.winner_name;
  v_old_winner_uid  := v_adoption.winner_user_id;

  -- 기존 당첨자를 제외한 잔여 신청자 중 랜덤 선택
  SELECT applicant_nickname, applicant_id INTO v_new_winner
    FROM adoption_applications
   WHERE adoption_id = p_adoption_id
     AND (
       (v_old_winner_uid IS NULL OR applicant_id IS DISTINCT FROM v_old_winner_uid)
       AND (
         v_old_winner_name IS NULL
         OR lower(trim(applicant_nickname)) IS DISTINCT FROM lower(trim(v_old_winner_name))
       )
     )
   ORDER BY random()
   LIMIT 1;

  IF v_new_winner IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '리추첨할 남은 신청자가 없어요.');
  END IF;

  UPDATE adoptions
     SET winner_name     = v_new_winner.applicant_nickname,
         winner_user_id  = v_new_winner.applicant_id,
         winner_drawn_at = now()
   WHERE id = p_adoption_id;

  v_link := 'adoption-detail.html?id=' || p_adoption_id;

  -- 새 당첨자 알림 (기존 당첨 알림 로직 재사용)
  IF v_new_winner.applicant_id IS NOT NULL THEN
    PERFORM public.notify_user_by_id(
      v_new_winner.applicant_id,
      'raffle_win',
      '🎲 랜덤 추첨 분양에 당첨되었습니다! 분양글에서 당첨 확인을 진행해 주세요.',
      v_link
    );
  END IF;

  -- 기존 당첨자 취소 알림
  IF v_old_winner_uid IS NOT NULL THEN
    PERFORM public.notify_user_by_id(
      v_old_winner_uid,
      'raffle_redraw_cancelled',
      '랜덤 추첨 분양 당첨 후 14일 동안 당첨 확인을 하지 않아 당첨이 취소되었습니다.',
      v_link
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'winner_name', v_new_winner.applicant_nickname,
    'winner_user_id', v_new_winner.applicant_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.redraw_adoption_raffle(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redraw_adoption_raffle(bigint) TO authenticated;
