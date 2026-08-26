-- ============================================================
-- 워터파컷 개체 소유권 일괄 연결 RPC
-- Supabase SQL Editor에서 실행 (CREATE OR REPLACE라 재실행해도 안전)
-- bulk_link_jellfirella_owner.sql을 그대로 복제해 species_name만 '워터파컷'으로 바꾼 버전.
--
-- 목적: 관리자 페이지(pages/waterpacut-bulk-transfer.html)에서 뽀가 직접 입력한
--       (사이트 유저, 워터파컷 개체번호) 조합만 처리한다.
--       characters.owner_nickname / owner_contact를 근거로 사이트 계정을
--       자동으로 찾아 연결하는 로직은 포함하지 않는다.
--
-- 입력: char_id / char_number / new_owner_user_id 세 값만 받는다.
--       new_owner_nickname·old_owner_nickname처럼 클라이언트가 계산해서
--       보낼 수 있는 값은 절대 받지 않고, 함수 내부에서 auth.users /
--       characters를 직접 조회해 서버 데이터만 사용한다.
--
-- 대상 조건 (전부 만족해야 UPDATE됨):
--   species_name = '워터파컷' AND owner_user_id IS NULL AND owner_is_offsite = true
--   → 뽀가 지정한 워터파컷 중 "현재 오프사이트 상태인 개체"만 연결 대상이 된다.
--
-- 권한: auth.users.raw_app_meta_data->>'role' = 'admin' 인 계정만 실행 가능.
-- ============================================================

CREATE OR REPLACE FUNCTION bulk_link_waterpacut_owner(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role    text;
  v_item           jsonb;
  v_char_id        bigint;
  v_char_number    text;
  v_new_owner_id   uuid;
  v_new_owner_nick text;
  v_old_owner_nick text;
  v_updated_count  integer := 0;
  v_skipped        jsonb   := '[]'::jsonb;
BEGIN
  SELECT raw_app_meta_data->>'role' INTO v_caller_role
    FROM auth.users WHERE id = auth.uid();

  IF v_caller_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION '권한이 없습니다. 관리자만 실행할 수 있습니다.';
  END IF;

  IF p_items IS NULL
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION '처리할 항목이 없습니다.';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_char_id      := (v_item->>'char_id')::bigint;
    v_char_number  := v_item->>'char_number';
    v_new_owner_id := (v_item->>'new_owner_user_id')::uuid;

    SELECT COALESCE(raw_user_meta_data->>'display_name', raw_user_meta_data->>'nickname')
      INTO v_new_owner_nick
      FROM auth.users WHERE id = v_new_owner_id;

    IF v_new_owner_nick IS NULL THEN
      v_skipped := v_skipped || jsonb_build_object(
        'char_id', v_char_id, 'char_number', v_char_number,
        'reason', '새 소유자 계정을 찾을 수 없음'
      );
      CONTINUE;
    END IF;

    SELECT owner_nickname INTO v_old_owner_nick
      FROM characters
     WHERE id = v_char_id
       AND char_number = v_char_number
       AND species_name = '워터파컷'
       AND owner_user_id IS NULL
       AND owner_is_offsite = true
     FOR UPDATE;

    IF NOT FOUND THEN
      v_skipped := v_skipped || jsonb_build_object(
        'char_id', v_char_id, 'char_number', v_char_number,
        'reason', '조건 불일치로 건너뜀 (워터파컷/오프사이트/소유자 미지정 조건 중 하나가 검증 이후 바뀜)'
      );
      CONTINUE;
    END IF;

    UPDATE characters
       SET owner_user_id    = v_new_owner_id,
           owner_nickname   = v_new_owner_nick,
           owner_is_offsite = false,
           owner_contact    = NULL,
           folder_id        = NULL,
           pending_transfer = NULL
     WHERE id = v_char_id;

    INSERT INTO character_transfers
      (character_id, character_name, species_name,
       from_user_id, from_nickname, to_user_id, to_nickname, method)
    SELECT id, name, '워터파컷', NULL, v_old_owner_nick, v_new_owner_id, v_new_owner_nick, '일괄 소유권 연결'
      FROM characters WHERE id = v_char_id;

    v_updated_count := v_updated_count + 1;
  END LOOP;

  INSERT INTO admin_logs
    (admin_id, admin_nickname, action_type, target_type, target_id, target_name, details)
  SELECT
    auth.uid(),
    COALESCE(raw_user_meta_data->>'display_name', raw_user_meta_data->>'nickname', 'admin'),
    'bulk_waterpacut_owner_link', 'character', NULL, '워터파컷 소유권 일괄 연결',
    jsonb_build_object('requested', jsonb_array_length(p_items), 'updated', v_updated_count, 'skipped', v_skipped)
  FROM auth.users WHERE id = auth.uid();

  RETURN jsonb_build_object('ok', true, 'updated', v_updated_count, 'skipped', v_skipped);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_link_waterpacut_owner(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bulk_link_waterpacut_owner(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.bulk_link_waterpacut_owner(jsonb) TO authenticated;
