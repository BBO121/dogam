-- ============================================
-- 대표 이미지(characters 기존 이미지)와 성장 Step 순서 분리
-- 작성일: 2026-07-27
-- species_steps.step_order는 순수 성장 순서만 담당하고,
-- 기존 대표 이미지를 어느 Step에서 쓸지는 species.main_image_step_id로 별도 지정한다.
-- ============================================

ALTER TABLE public.species
ADD COLUMN IF NOT EXISTS main_image_step_id bigint
  REFERENCES public.species_steps(id)
  ON DELETE SET NULL;

COMMENT ON COLUMN public.species.main_image_step_id IS
'기존 characters 대표 이미지(image_url/original_image_url/thumbnail_url)를 사용할 species_steps.id. NULL이면 하위 호환을 위해 step_order가 가장 낮은 Step을 대표 이미지 Step으로 처리한다.';

-- ============================================
-- main_image_step_id 종족 일치 검증 (트리거)
-- 외래키(REFERENCES species_steps(id))는 해당 Step이 "존재"하는지만 보장하고
-- 그 Step이 이 종족(species_id) 소유인지는 보장하지 못하므로 트리거로 별도 검증한다.
-- ============================================

CREATE OR REPLACE FUNCTION public.check_main_image_step_species()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.main_image_step_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.species_steps ss
      WHERE ss.id = NEW.main_image_step_id
        AND ss.species_id = NEW.id
    ) THEN
      RAISE EXCEPTION '대표 이미지 Step은 반드시 같은 종족(species_id)에 속한 Step이어야 합니다.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_main_image_step_species ON public.species;

CREATE TRIGGER trg_check_main_image_step_species
BEFORE INSERT OR UPDATE OF main_image_step_id ON public.species
FOR EACH ROW
EXECUTE FUNCTION public.check_main_image_step_species();

-- ============================================
-- Step 순서 UNIQUE 제약을 지연 가능하도록 변경
-- (순서 변경 중간에 두 Step이 잠깐 같은 step_order를 갖는 것을 허용해
-- 스왑/재정렬 시 충돌 없이 처리하기 위함 — 실제 검사는 트랜잭션 커밋 시점)
-- ============================================

ALTER TABLE public.species_steps
DROP CONSTRAINT IF EXISTS species_steps_species_id_step_order_key;

ALTER TABLE public.species_steps
ADD CONSTRAINT species_steps_species_id_step_order_key
  UNIQUE (species_id, step_order)
  DEFERRABLE INITIALLY IMMEDIATE;

-- ============================================
-- Step 순서 일괄 재정렬 RPC
-- p_step_ids: 원하는 최종 순서대로 나열한 species_steps.id 배열 (1번째 → step_order 1 ...)
-- 반드시 해당 종족의 모든 Step ID를 정확히 한 번씩 포함해야 하며,
-- 다른 종족의 Step ID나 중복/누락이 있으면 거부한다.
-- 호출자가 해당 종족의 종족주이거나 admin/staff인 경우에만 실행된다.
-- ============================================

CREATE OR REPLACE FUNCTION public.reorder_species_steps(
  p_species_id bigint,
  p_step_ids   bigint[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_id       uuid;
  v_caller_role    text;
  v_total_count    integer;
  v_input_count    integer;
  v_distinct_count integer;
  v_valid_count    integer;
  i                integer;
BEGIN
  -- 로그인 확인
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 종족 조회
  SELECT s.owner_user_id
  INTO v_owner_id
  FROM public.species s
  WHERE s.id = p_species_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '종족을 찾을 수 없습니다.';
  END IF;

  -- JWT 기반 역할 확인
  v_caller_role := auth.jwt() -> 'user_metadata' ->> 'role';

  -- 권한 확인
  IF v_owner_id IS DISTINCT FROM auth.uid()
     AND COALESCE(v_caller_role, '') NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '권한이 없습니다. 종족주만 순서를 변경할 수 있습니다.';
  END IF;

  -- NULL 배열 방지
  IF p_step_ids IS NULL THEN
    RAISE EXCEPTION 'Step 순서 배열이 필요합니다.';
  END IF;

  v_input_count := COALESCE(cardinality(p_step_ids), 0);

  -- NULL 원소 방지 (unnest/ANY의 NULL 비교 특성상 조용히 잘못된 결과를 낼 수 있어 명시적으로 차단)
  IF EXISTS (SELECT 1 FROM unnest(p_step_ids) AS t(step_id) WHERE step_id IS NULL) THEN
    RAISE EXCEPTION 'Step 순서 배열에 NULL 값이 포함될 수 없습니다.';
  END IF;

  -- 해당 종족 전체 Step 수
  SELECT COUNT(*)
  INTO v_total_count
  FROM public.species_steps ss
  WHERE ss.species_id = p_species_id;

  -- Step이 없으면 빈 배열만 허용
  IF v_total_count = 0 THEN
    IF v_input_count <> 0 THEN
      RAISE EXCEPTION '해당 종족에 등록된 Step이 없습니다.';
    END IF;

    RETURN;
  END IF;

  -- Step이 있는데 빈 배열이면 거부
  IF v_input_count = 0 THEN
    RAISE EXCEPTION '최소 하나 이상의 Step이 필요합니다.';
  END IF;

  -- 중복 ID 검사
  SELECT COUNT(DISTINCT step_id)
  INTO v_distinct_count
  FROM unnest(p_step_ids) AS t(step_id);

  IF v_distinct_count <> v_input_count THEN
    RAISE EXCEPTION 'Step 순서 배열에 중복된 ID가 있습니다.';
  END IF;

  -- 배열 안에서 실제 해당 종족에 속한 Step 수
  SELECT COUNT(*)
  INTO v_valid_count
  FROM public.species_steps ss
  WHERE ss.species_id = p_species_id
    AND ss.id = ANY(p_step_ids);

  -- 빠진 Step 또는 다른 종족 Step 방지
  IF v_input_count <> v_total_count
     OR v_valid_count <> v_total_count THEN
    RAISE EXCEPTION
      'Step 순서 배열은 해당 종족의 모든 Step ID를 정확히 한 번씩 포함해야 합니다.';
  END IF;

  -- 순서 변경 중 UNIQUE 충돌 방지
  SET CONSTRAINTS species_steps_species_id_step_order_key DEFERRED;

  FOR i IN 1..v_input_count LOOP
    UPDATE public.species_steps
    SET
      step_order = i,
      updated_at = now()
    WHERE id = p_step_ids[i]
      AND species_id = p_species_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION '유효하지 않은 Step ID가 포함되어 있습니다: %', p_step_ids[i];
    END IF;
  END LOOP;
END;
$$;

-- SECURITY DEFINER 함수 실행 권한 제한
REVOKE ALL
ON FUNCTION public.reorder_species_steps(bigint, bigint[])
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.reorder_species_steps(bigint, bigint[])
TO authenticated;
