-- 디자인권 분양 확인 처리 RPC
-- SECURITY DEFINER: RLS 우회 + slots/adoptions 원자 처리
-- winner_name으로 당첨자 검증, owner_user_id는 UUID 기준

CREATE OR REPLACE FUNCTION confirm_slot_adoption_transfer(
  p_adoption_id    bigint,
  p_new_owner_id   uuid,
  p_new_owner_nick text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_slot_id uuid;
  v_winner  text;
BEGIN
  -- 분양 정보 조회 및 당첨자 검증
  SELECT slot_id, winner_name
    INTO v_slot_id, v_winner
    FROM adoptions
   WHERE id = p_adoption_id
     AND status = '확인 대기중';

  IF v_slot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '유효하지 않은 분양이거나 이미 완료됐어요.');
  END IF;

  IF v_winner IS DISTINCT FROM p_new_owner_nick THEN
    RETURN jsonb_build_object('ok', false, 'error', '당첨자 정보가 일치하지 않아요.');
  END IF;

  -- slots 소유권 이전 (UUID 기준, owner_name 초기화)
  UPDATE slots
     SET owner_user_id = p_new_owner_id,
         owner_name    = NULL
   WHERE id = v_slot_id;

  -- adoptions 완료 처리
  UPDATE adoptions
     SET status = '완료'
   WHERE id = p_adoption_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;
