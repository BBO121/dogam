-- 서버 시간 조회 함수 (KST 표시용 UTC 기준)
CREATE OR REPLACE FUNCTION get_server_time()
RETURNS timestamptz
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  SELECT now();
$$;

GRANT EXECUTE ON FUNCTION get_server_time() TO anon;
GRANT EXECUTE ON FUNCTION get_server_time() TO authenticated;
