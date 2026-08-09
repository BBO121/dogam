-- ============================================================
-- 테일스 개체 소유권 일괄 연결 RPC (v2)
-- Supabase SQL Editor에서 실행 (CREATE OR REPLACE라 재실행해도 안전)
--
-- 목적: 관리자 페이지(pages/tails-bulk-transfer.html)에서 뽀가 직접 입력한
--       (사이트 유저, 테일스 개체번호) 조합만 처리한다.
--       characters.owner_nickname / owner_contact를 근거로 사이트 계정을
--       자동으로 찾아 연결하는 로직은 포함하지 않는다.
--
-- 입력: char_id / char_number / new_owner_user_id 세 값만 받는다.
--       new_owner_nickname·old_owner_nickname처럼 클라이언트가 계산해서
--       보낼 수 있는 값은 절대 받지 않고, 함수 내부에서 auth.users /
--       characters를 직접 조회해 서버 데이터만 사용한다.
--
-- 대상 조건 (전부 만족해야 UPDATE됨):
--   species_name = '테일스' AND owner_user_id IS NULL AND owner_is_offsite = true
--   → 뽀가 지정한 테일스 중 "현재 오프사이트 상태인 개체"만 연결 대상이 된다.
--
-- 권한: auth.users.raw_app_meta_data->>'role' = 'admin' 인 계정만 실행 가능.
--       raw_app_meta_data는 Supabase Admin API(service_role) 또는 DB
--       직접 접근으로만 바꿀 수 있고, 유저 본인이 supabase.auth.updateUser()로
--       고칠 수 있는 raw_user_meta_data와 분리되어 있다. 이 프로젝트의 다른 RPC
--       상당수는 아직 raw_user_meta_data.role을 쓰지만(유저가 자기 걸 바꿀 수 있어
--       원칙적으로 불안전), 소유권을 실제로 바꾸는 이 함수는 안전한 쪽을 쓴다.
--
--       ⚠️ 실행 전 준비: 이 함수를 호출할 관리자 계정에 app_metadata.role='admin'이
--       미리 설정되어 있어야 한다. supabase/app_metadata_role_seed.sql의 STEP 1로
--       현재 app_metadata.role이 설정된 계정을 확인하고, 없다면 STEP 2 방식으로
--       (실제로 admin이 맞는지 직접 확인한 UUID만) 채워 넣을 것.
-- ============================================================

CREATE OR REPLACE FUNCTION bulk_link_tails_owner(p_items jsonb)
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
  -- 관리자 판정: app_metadata.role만 신뢰한다 (user_metadata는 본인이 조작 가능)
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

    -- 새 소유자 닉네임 — 클라이언트 입력 대신 서버에서 직접 조회
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

    -- 대상 행을 잠그고 현재 owner_nickname을 서버에서 직접 확보 (클라이언트 값 미사용)
    -- 조건: 이 개체번호의 테일스 + 소유자 미지정 + 오프사이트 상태
    SELECT owner_nickname INTO v_old_owner_nick
      FROM characters
     WHERE id = v_char_id
       AND char_number = v_char_number
       AND species_name = '테일스'
       AND owner_user_id IS NULL
       AND owner_is_offsite = true
     FOR UPDATE;

    IF NOT FOUND THEN
      v_skipped := v_skipped || jsonb_build_object(
        'char_id', v_char_id, 'char_number', v_char_number,
        'reason', '조건 불일치로 건너뜀 (테일스/오프사이트/소유자 미지정 조건 중 하나가 검증 이후 바뀜)'
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
    SELECT id, name, '테일스', NULL, v_old_owner_nick, v_new_owner_id, v_new_owner_nick, '일괄 소유권 연결'
      FROM characters WHERE id = v_char_id;

    v_updated_count := v_updated_count + 1;
  END LOOP;

  INSERT INTO admin_logs
    (admin_id, admin_nickname, action_type, target_type, target_id, target_name, details)
  SELECT
    auth.uid(),
    COALESCE(raw_user_meta_data->>'display_name', raw_user_meta_data->>'nickname', 'admin'),
    'bulk_tails_owner_link', 'character', NULL, '테일스 소유권 일괄 연결',
    jsonb_build_object('requested', jsonb_array_length(p_items), 'updated', v_updated_count, 'skipped', v_skipped)
  FROM auth.users WHERE id = auth.uid();

  RETURN jsonb_build_object('ok', true, 'updated', v_updated_count, 'skipped', v_skipped);
END;
$$;

-- 실행 권한을 명시적으로 제한한다. GRANT authenticated만으로 기존 PUBLIC 실행
-- 권한이 자동으로 사라진다고 가정하지 않고, PUBLIC/anon을 먼저 명시적으로 REVOKE한다.
REVOKE ALL ON FUNCTION public.bulk_link_tails_owner(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bulk_link_tails_owner(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.bulk_link_tails_owner(jsonb) TO authenticated;
