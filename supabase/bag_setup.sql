-- ============================================
-- 내 가방 / 프레임 장착 시스템 DB 설정
-- 작성일: 2026-06-21
-- 수정일: 2026-06-21 (user_equipment 별도 테이블, user_id 기준)
--
-- 설계 원칙:
--   상점/가방/장착은 전부 user_id(auth.uid()) 기준
--   nickname은 표시용으로만 사용
--   user_profiles(PK=nickname) 건드리지 않음
-- ============================================

-- ── 1. shop_items에 style_key 컬럼 추가 ─────
--  CSS 프레임 클래스 등 프론트 렌더링 키 저장
--  예: 'frame-mint', 'frame-orange'
ALTER TABLE public.shop_items
ADD COLUMN IF NOT EXISTS style_key text;


-- ── 2. user_equipment 테이블 ─────────────────
--  장착 상태 전용 테이블
--  user_id = PRIMARY KEY → 닉네임 변경 영향 없음
--  향후 equipped_title_id, equipped_deco_id 등 확장 가능
CREATE TABLE IF NOT EXISTS public.user_equipment (
  user_id           uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  equipped_frame_id uuid        REFERENCES public.shop_items(id) ON DELETE SET NULL,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ── 3. RLS 활성화 ────────────────────────────
ALTER TABLE public.user_equipment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "equipment: select own" ON public.user_equipment;
CREATE POLICY "equipment: select own"
  ON public.user_equipment FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT / UPDATE는 RPC(SECURITY DEFINER)로만 처리


-- ── 4. equip_frame RPC ───────────────────────
--  프레임 장착 — 전 구간 user_id 기준
--  검증: 로그인 / 아이템 존재 / 프레임 타입 / 보유 여부
--  처리: user_equipment UPSERT (user_id PK이므로 안전)
CREATE OR REPLACE FUNCTION equip_frame(p_item_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_item    record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 아이템 존재 확인
  SELECT * INTO v_item FROM public.shop_items WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  -- 프레임 타입 확인
  IF v_item.item_type != 'frame' THEN
    RETURN json_build_object('success', false, 'error', 'NOT_A_FRAME');
  END IF;

  -- 보유 여부 확인
  IF NOT EXISTS (
    SELECT 1 FROM public.user_items
    WHERE user_id = v_user_id AND item_id = p_item_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'NOT_OWNED');
  END IF;

  -- 장착 상태 저장 (user_id PK이므로 UPSERT 안전)
  INSERT INTO public.user_equipment (user_id, equipped_frame_id, updated_at)
  VALUES (v_user_id, p_item_id, now())
  ON CONFLICT (user_id) DO UPDATE
  SET equipped_frame_id = p_item_id,
      updated_at        = now();

  RETURN json_build_object(
    'success',           true,
    'equipped_frame_id', p_item_id,
    'style_key',         v_item.style_key
  );
END;
$$;

GRANT EXECUTE ON FUNCTION equip_frame(uuid) TO authenticated;


-- ── 5. unequip_frame RPC ─────────────────────
--  프레임 해제 — equipped_frame_id = NULL
CREATE OR REPLACE FUNCTION unequip_frame()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid    := auth.uid();
  v_rows    integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  UPDATE public.user_equipment
  SET equipped_frame_id = NULL,
      updated_at        = now()
  WHERE user_id = v_user_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    -- row 없으면 해제 상태와 동일 → 성공으로 처리
    RETURN json_build_object('success', true, 'equipped_frame_id', null);
  END IF;

  RETURN json_build_object('success', true, 'equipped_frame_id', null);
END;
$$;

GRANT EXECUTE ON FUNCTION unequip_frame() TO authenticated;


-- ── 6. 인덱스 ────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_user_equipment_frame
  ON public.user_equipment (equipped_frame_id)
  WHERE equipped_frame_id IS NOT NULL;
