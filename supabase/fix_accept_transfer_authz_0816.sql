-- ============================================================
-- [긴급] accept_transfer RPC 호출자 인가 누락 수정
-- 작성일: 2026-08-16
-- 라이브 함수 확인 완료 (뽀, 2026-08-16): auth.uid() 존재만 확인하고
-- pending_transfer 존재/수신자 검증 없이 임의 p_char_id의 소유권을
-- 호출자에게 즉시 이전하는 취약한 버전임을 확인.
--
-- 이번 패치 반영 사항:
--   1) 캐릭터 조회 시 FOR UPDATE로 잠가 동시 호출 race condition 방지
--   2) pending_transfer NULL이면 거부
--   3) 수신자 검증: to_user_id 있으면 uuid 일치, 없으면(레거시) nickname만 fallback
--   4) p_new_owner_nick(클라이언트 입력) 대신 auth.users에서 조회한
--      호출자의 실제 닉네임(v_caller_nick)을 owner_nickname/to_nickname에 사용
--   5) stale pending_transfer 차단: from_user_id가 있으면 현재
--      characters.owner_user_id와 일치해야 함 (소유주가 이미 바뀐 뒤
--      남아있는 오래된 요청 재사용 방지)
--   6) method는 pending_transfer.method 우선, 없으면 'link'
--   7) SECURITY DEFINER 유지 + search_path 고정, 테이블 스키마 명시
-- ============================================================

CREATE OR REPLACE FUNCTION accept_transfer(
  p_char_id        bigint,
  p_new_owner_nick text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_uid  uuid := auth.uid();
  v_char        record;
  v_pending     jsonb;
  v_caller_nick text;
  v_method      text;
BEGIN
  IF v_caller_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '로그인이 필요해요.');
  END IF;

  -- 개체 조회 + 잠금 (동시 호출 race condition 방지)
  SELECT * INTO v_char
    FROM public.characters
   WHERE id = p_char_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', '개체를 찾을 수 없어요.');
  END IF;

  v_pending := v_char.pending_transfer;

  -- 이전 대기 상태가 아니면 거부
  IF v_pending IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '이전 대기 중인 개체가 아니에요.');
  END IF;

  -- stale 요청 차단: 요청 당시 소유주와 현재 소유주가 다르면(이미 처리/변경됨) 거부
  IF (v_pending ->> 'from_user_id') IS NOT NULL
     AND (v_pending ->> 'from_user_id')::uuid <> v_char.owner_user_id THEN
    RETURN jsonb_build_object('ok', false, 'error', '유효하지 않은 이전 요청이에요.');
  END IF;

  -- 호출자의 실제 닉네임 조회 (클라이언트 입력 p_new_owner_nick은 신뢰하지 않음)
  SELECT COALESCE(NULLIF(raw_user_meta_data ->> 'display_name', ''), raw_user_meta_data ->> 'nickname')
    INTO v_caller_nick
    FROM auth.users
   WHERE id = v_caller_uid;

  -- 수신자 검증: to_user_id 우선, 없으면(레거시) nickname만 fallback
  IF (v_pending ->> 'to_user_id') IS NOT NULL THEN
    IF (v_pending ->> 'to_user_id')::uuid <> v_caller_uid THEN
      RETURN jsonb_build_object('ok', false, 'error', '이 이전 요청은 나에게 온 요청이 아니에요.');
    END IF;
  ELSE
    IF v_caller_nick IS NULL OR v_caller_nick <> (v_pending ->> 'to') THEN
      RETURN jsonb_build_object('ok', false, 'error', '이 이전 요청은 나에게 온 요청이 아니에요.');
    END IF;
  END IF;

  v_method := COALESCE(v_pending ->> 'method', 'link');

  -- 소유권 이전 + folder_id / pending_transfer 초기화
  UPDATE public.characters
     SET owner_user_id    = v_caller_uid,
         owner_nickname   = v_caller_nick,
         folder_id        = NULL,
         pending_transfer = NULL
   WHERE id = p_char_id;

  -- 이전 기록 남기기
  INSERT INTO public.character_transfers
    (character_id, character_name, species_name,
     from_user_id, from_nickname,
     to_user_id,   to_nickname,
     method)
  VALUES
    (p_char_id, v_char.name, v_char.species_name,
     v_char.owner_user_id, v_char.owner_nickname,
     v_caller_uid,         v_caller_nick,
     v_method);

  RETURN jsonb_build_object('ok', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION accept_transfer(bigint, text) TO authenticated;
