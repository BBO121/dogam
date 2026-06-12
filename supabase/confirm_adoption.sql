-- 캐릭터 분양 확인 처리 RPC (당첨자 본인 확인하기 버튼)
-- SECURITY DEFINER: RLS 우회 + characters/adoptions 원자 처리
-- 검증 우선순위: winner_user_id(auth.uid) → winner_name 정규화 비교 (구데이터 폴백)
-- p_new_owner_nick 은 검증용이 아닌 characters.owner_nickname 기록용으로만 사용

CREATE OR REPLACE FUNCTION confirm_adoption_transfer(
  p_adoption_id    bigint,
  p_new_owner_id   uuid,
  p_new_owner_nick text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_character_id bigint;
  v_winner_uid   uuid;
  v_winner_name  text;
  v_caller_uid   uuid := auth.uid();
BEGIN
  -- 분양 정보 조회
  SELECT character_id, winner_user_id, winner_name
    INTO v_character_id, v_winner_uid, v_winner_name
    FROM adoptions
   WHERE id = p_adoption_id
     AND status = '확인 대기중';

  IF v_character_id IS NULL THEN
    RAISE EXCEPTION '유효하지 않은 분양이거나 이미 완료됐어요.';
  END IF;

  -- 당첨자 검증: winner_user_id 있으면 auth.uid() 비교, 없으면 닉네임 정규화 비교
  IF v_winner_uid IS NOT NULL THEN
    IF v_caller_uid IS DISTINCT FROM v_winner_uid THEN
      RAISE EXCEPTION '당첨자 UID가 일치하지 않아요.';
    END IF;
  ELSE
    IF lower(trim(v_winner_name)) IS DISTINCT FROM lower(trim(p_new_owner_nick)) THEN
      RAISE EXCEPTION 'winner_mismatch: winner_name=%, requested=%', v_winner_name, p_new_owner_nick;
    END IF;
  END IF;

  -- characters 소유권 이전
  UPDATE characters
     SET owner_user_id = p_new_owner_id,
         owner_nickname = p_new_owner_nick
   WHERE id = v_character_id;

  -- adoptions 완료 처리
  UPDATE adoptions
     SET status = '완료'
   WHERE id = p_adoption_id;
END;
$$;
