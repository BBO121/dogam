-- notify_user_by_id: UUID 기반으로 notifications 테이블에 알림 INSERT
-- SECURITY DEFINER: RLS를 우회하여 서버 측에서 안전하게 알림 생성
-- auth.users에서 닉네임을 자동 조회하여 user_nickname도 함께 저장
-- display_name → nickname → email 순으로 fallback
-- 호출 측은 authenticated 권한만 사용 가능

CREATE OR REPLACE FUNCTION public.notify_user_by_id(
  p_user_id uuid,
  p_type    text,
  p_message text,
  p_link    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nickname text;
BEGIN
  -- 잘못된 UUID 방지
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  -- auth.users에서 닉네임 조회
  -- display_name → nickname → email 순으로 사용
  SELECT COALESCE(
    raw_user_meta_data->>'display_name',
    raw_user_meta_data->>'nickname',
    email
  )
  INTO v_nickname
  FROM auth.users
  WHERE id = p_user_id;

  INSERT INTO public.notifications (
    user_id,
    user_nickname,
    type,
    message,
    link
  )
  VALUES (
    p_user_id,
    v_nickname,
    p_type,
    p_message,
    p_link
  );
END;
$$;

-- 기본 권한 제거
REVOKE ALL
ON FUNCTION public.notify_user_by_id(uuid, text, text, text)
FROM PUBLIC;

-- 로그인한 사용자만 실행 가능
GRANT EXECUTE
ON FUNCTION public.notify_user_by_id(uuid, text, text, text)
TO authenticated;
