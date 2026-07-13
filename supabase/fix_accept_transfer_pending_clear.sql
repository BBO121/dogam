-- ============================================================
-- 이전 수락 후 pending_transfer가 초기화되지 않는 버그 수정
-- 작성일: 2026-07-06
-- 증상: 이전(character-transfer.html → transfer-confirm.html)을
--       수락하면 소유주는 바뀌지만 characters.pending_transfer 값이
--       그대로 남아 캐릭터 상세 상단의 "이전 확인 중" 배너가
--       사라지지 않음
-- 원인: accept_transfer RPC가 owner_user_id / owner_nickname /
--       folder_id만 초기화하고 pending_transfer는 NULL 처리하지 않음
-- ============================================================

-- ── 1. accept_transfer RPC 수정 ──────────────────────────
--    기존 로직(folder_on_transfer 수정분 포함)을 그대로 보존,
--    pending_transfer = NULL 만 추가

CREATE OR REPLACE FUNCTION accept_transfer(
  p_char_id        bigint,
  p_new_owner_nick text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_uid uuid := auth.uid();
  v_char       record;
BEGIN
  IF v_caller_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '로그인이 필요해요.');
  END IF;

  -- 개체 조회
  SELECT * INTO v_char FROM characters WHERE id = p_char_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', '개체를 찾을 수 없어요.');
  END IF;

  -- 소유권 이전 + folder_id / pending_transfer 초기화
  UPDATE characters
     SET owner_user_id    = v_caller_uid,
         owner_nickname   = p_new_owner_nick,
         folder_id        = NULL,
         pending_transfer = NULL
   WHERE id = p_char_id;

  -- 이전 기록 남기기
  INSERT INTO character_transfers
    (character_id, character_name, species_name,
     from_user_id, from_nickname,
     to_user_id,   to_nickname,
     method)
  VALUES
    (p_char_id, v_char.name, v_char.species_name,
     v_char.owner_user_id, v_char.owner_nickname,
     v_caller_uid,         p_new_owner_nick,
     'link');

  RETURN jsonb_build_object('ok', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION accept_transfer(bigint, text) TO authenticated;


-- ── 2. 기존 오염 데이터 일괄 정리 ─────────────────────
--    이미 이전이 완료됐지만(현재 소유자가 pending_transfer.to와 동일)
--    pending_transfer가 남아있는 캐릭터를 정리

UPDATE characters
   SET pending_transfer = NULL
 WHERE pending_transfer IS NOT NULL
   AND owner_nickname = pending_transfer->>'to';
