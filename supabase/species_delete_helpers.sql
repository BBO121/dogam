-- ================================================================
-- 종족 삭제 관련 헬퍼 함수
-- Supabase SQL Editor에서 실행해주세요.
-- 이미 실행한 경우 다시 실행하면 함수가 업데이트됩니다 (CREATE OR REPLACE).
-- ================================================================

-- 1. 분양 이력 존재 여부 확인
--    adoptions 테이블의 RLS를 우회하여 정확히 조회합니다.
CREATE OR REPLACE FUNCTION check_species_has_adoptions(p_species_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM adoptions WHERE species_name = TRIM(p_species_name)
  );
END;
$$;


-- 2. 종족 삭제 시 소속 개체 species_name 초기화
--    characters 테이블의 RLS를 우회하여 타인 소유 개체도 일괄 업데이트합니다.
--    호출자가 해당 종족의 소유자이거나 admin/staff인 경우에만 실행됩니다.
CREATE OR REPLACE FUNCTION nullify_deleted_species_chars(p_species_id BIGINT, p_species_name TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id    UUID;
  v_caller_role TEXT;
  updated_count INTEGER;
BEGIN
  -- 종족 소유자 확인
  SELECT owner_user_id INTO v_owner_id
  FROM species WHERE id = p_species_id;

  -- 호출자 역할 확인
  SELECT raw_user_meta_data->>'role' INTO v_caller_role
  FROM auth.users WHERE id = auth.uid();

  -- 소유자 또는 admin/staff만 허용
  IF v_owner_id IS DISTINCT FROM auth.uid()
     AND v_caller_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '권한이 없습니다. 종족 소유자만 실행할 수 있습니다.';
  END IF;

  -- TRIM으로 앞뒤 공백 제거 후 비교 (종족명 불일치 방지)
  UPDATE characters
  SET species_name = '(알 수 없음)'
  WHERE species_name = TRIM(p_species_name);

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;


-- ================================================================
-- 실행 권한 부여
-- authenticated: 로그인한 일반 유저 (종족주)
-- ================================================================
GRANT EXECUTE ON FUNCTION check_species_has_adoptions(TEXT)              TO authenticated, anon;
GRANT EXECUTE ON FUNCTION nullify_deleted_species_chars(BIGINT, TEXT)    TO authenticated;
