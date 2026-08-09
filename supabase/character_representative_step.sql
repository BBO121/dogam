-- ============================================
-- 개체별 대표 이미지 Step 오버라이드
-- (융용 등 개체마다 대표 Step이 달라지는 종족용)
-- 작성일: 2026-08-09
--
-- 기존 species.main_image_step_id는
-- 종족 전체에 고정된 대표 Step만 지정 가능했음.
--
-- characters.representative_step_id가 채워져 있으면
-- 해당 개체는 이 Step을 대표 이미지 Step으로 우선 사용한다.
--
-- NULL이면 하위 호환:
-- 기존처럼 species.main_image_step_id를 사용한다.
-- ============================================


-- 1. 개체별 대표 Step 컬럼 추가
ALTER TABLE public.characters
ADD COLUMN IF NOT EXISTS representative_step_id bigint
  REFERENCES public.species_steps(id)
  ON DELETE SET NULL;


COMMENT ON COLUMN public.characters.representative_step_id IS
'이 개체의 대표 이미지(characters.image_url/thumbnail_url/original_image_url)가 실제로 어느 species_steps.id의 이미지인지 기록. NULL이면 하위 호환으로 species.main_image_step_id를 사용한다.';


-- ============================================
-- 2. 대표 Step과 개체 종족 일치 검증 함수
--
-- FK는 species_steps.id가 존재하는지만 보장하므로,
-- 선택된 Step이 실제로 해당 개체의 종족에 속하는지도 검증한다.
--
-- 예:
-- 융용 개체 → 융용의 Step만 representative_step_id로 지정 가능
-- ============================================

CREATE OR REPLACE FUNCTION public.check_representative_step_species()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.representative_step_id IS NOT NULL THEN

    IF NOT EXISTS (
      SELECT 1
      FROM public.species_steps ss
      JOIN public.species s
        ON s.id = ss.species_id
      WHERE ss.id = NEW.representative_step_id
        AND s.name = NEW.species_name
    ) THEN
      RAISE EXCEPTION
        '대표 이미지 Step은 반드시 이 개체와 같은 종족의 Step이어야 합니다.';
    END IF;

  END IF;

  RETURN NEW;
END;
$$;


-- ============================================
-- 3. 기존 트리거가 있다면 제거
-- ============================================

DROP TRIGGER IF EXISTS trg_check_representative_step_species
ON public.characters;


-- ============================================
-- 4. 검증 트리거 생성
--
-- representative_step_id 변경뿐 아니라
-- species_name이 변경되는 경우에도 다시 검증한다.
--
-- 따라서:
-- - 다른 종족의 Step을 대표로 지정하는 경우 차단
-- - 대표 Step이 지정된 상태에서 종족만 변경하여
--   불일치 상태가 되는 경우도 차단
-- ============================================

CREATE TRIGGER trg_check_representative_step_species
BEFORE INSERT OR UPDATE OF representative_step_id, species_name
ON public.characters
FOR EACH ROW
EXECUTE FUNCTION public.check_representative_step_species();


-- ============================================
-- 5. 적용 확인
-- ============================================

SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'characters'
  AND column_name = 'representative_step_id';