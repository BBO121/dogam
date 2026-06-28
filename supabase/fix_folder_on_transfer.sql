-- ============================================================
-- 캐릭터 이전 시 folder_id 초기화 누락 버그 수정
-- 작성일: 2026-06-28
-- 증상: 이전받은 캐릭터가 내 캐릭터 "미분류"에 나타나지 않음
-- 원인: accept_transfer / confirm_adoption_transfer RPC가
--       owner_user_id만 바꾸고 folder_id를 NULL로 초기화하지 않음
-- ============================================================

-- ── 1. accept_transfer RPC 수정 ──────────────────────────
--    (직접 이전 — transfer-confirm.html 에서 호출)
--    기존 함수가 DB에만 존재하므로 CREATE OR REPLACE 로 덮어씀
--    ※ 기존 로직을 최대한 보존, folder_id = NULL 만 추가

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

  -- 소유권 이전 + folder_id 초기화
  UPDATE characters
     SET owner_user_id  = v_caller_uid,
         owner_nickname = p_new_owner_nick,
         folder_id      = NULL
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
--    현재 소유자의 폴더가 아닌 folder_id를 가진 캐릭터를 NULL 처리
--    (이미 이전됐지만 folder_id가 남아있는 캐릭터)

UPDATE characters c
   SET folder_id = NULL
 WHERE c.folder_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1
       FROM character_folders f
      WHERE f.id      = c.folder_id
        AND f.user_id = c.owner_user_id
   );
