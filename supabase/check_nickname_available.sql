-- 닉네임 중복 체크 RPC
-- 목적: 회원가입 및 display_name 변경 시 닉네임 중복 방지
-- 비교 기준: auth.users.raw_user_meta_data->>'display_name' (없으면 'nickname')
-- 적용 규칙: trim + lower / 본인 계정 제외 / anon·authenticated 둘 다 허용

CREATE OR REPLACE FUNCTION public.check_nickname_available(p_nickname text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized text := lower(trim(p_nickname));
BEGIN
  IF v_normalized = '' THEN
    RETURN false;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE lower(trim(
            COALESCE(
              NULLIF(raw_user_meta_data->>'display_name', ''),
              raw_user_meta_data->>'nickname'
            )
          )) = v_normalized
      -- 본인 계정 제외 (미인증 상태이면 auth.uid() = NULL → 제외 조건 없음)
      AND (auth.uid() IS NULL OR id != auth.uid())
  );
END;
$$;

-- anon: 회원가입 시 (미인증 상태)
-- authenticated: 닉네임 변경 시
GRANT EXECUTE ON FUNCTION public.check_nickname_available(text) TO anon, authenticated;
