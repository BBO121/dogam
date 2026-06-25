-- 유저 목록 전용 함수 (users.html)
-- auth.users 전체 기준, 닉네임 미설정자도 포함
-- login_id: raw_user_meta_data 우선, 없으면 email @ 앞부분 추출
-- deleted_at IS NOT NULL 제외

CREATE OR REPLACE FUNCTION get_all_users_full()
RETURNS TABLE (
  id          uuid,
  nickname    text,
  login_id    text,
  role        text,
  created_at  timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    u.id,
    NULLIF(TRIM(COALESCE(
      u.raw_user_meta_data->>'display_name',
      u.raw_user_meta_data->>'nickname',
      ''
    )), '') AS nickname,
    COALESCE(
      NULLIF(TRIM(u.raw_user_meta_data->>'login_id'), ''),
      SPLIT_PART(u.email, '@', 1)
    ) AS login_id,
    u.raw_user_meta_data->>'role' AS role,
    u.created_at
  FROM auth.users u
  WHERE u.deleted_at IS NULL
  ORDER BY u.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION get_all_users_full() TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_users_full() TO anon;
