-- ============================================
-- 스티커 시스템 DB 설계
-- 작성일: 2026-06-22
-- ============================================

-- ── 1. user_equipment에 equipped_sticker_id 추가 ──
ALTER TABLE public.user_equipment
ADD COLUMN IF NOT EXISTS equipped_sticker_id uuid
  REFERENCES public.shop_items(id) ON DELETE SET NULL;

-- ── 2. 스티커 RLS 정책 (user_equipment update) ──
DROP POLICY IF EXISTS "equipment: update own" ON public.user_equipment;
-- INSERT / UPDATE는 RPC(SECURITY DEFINER)로만 처리 → 별도 정책 불필요

-- ── 3. 공오 스티커 상품 추가 (재실행 안전) ──
INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, sort_order)
SELECT
  'sticker',
  '공오 스티커',
  '공오가 슬쩍 붙어있다',
  'research_records',
  0,
  'active',
  '../images/shop/sticker_free_05.png',
  'sticker-free-05',
  '기본',
  10
WHERE NOT EXISTS (
  SELECT 1
  FROM public.shop_items
  WHERE style_key = 'sticker-free-05'
);

-- ── 4. equip_sticker RPC ──
CREATE OR REPLACE FUNCTION equip_sticker(p_item_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_item    record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  SELECT * INTO v_item
  FROM public.shop_items
  WHERE id = p_item_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  IF v_item.item_type != 'sticker' THEN
    RETURN json_build_object('success', false, 'error', 'NOT_A_STICKER');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_items
    WHERE user_id = v_user_id
      AND item_id = p_item_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'NOT_OWNED');
  END IF;

  INSERT INTO public.user_equipment (
    user_id,
    equipped_sticker_id,
    updated_at
  )
  VALUES (
    v_user_id,
    p_item_id,
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET equipped_sticker_id = p_item_id,
      updated_at = now();

  RETURN json_build_object(
    'success', true,
    'equipped_sticker_id', p_item_id,
    'image_url', v_item.image_url
  );
END;
$$;

GRANT EXECUTE ON FUNCTION equip_sticker(uuid) TO authenticated;

-- ── 5. unequip_sticker RPC ──
CREATE OR REPLACE FUNCTION unequip_sticker()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  UPDATE public.user_equipment
  SET equipped_sticker_id = NULL,
      updated_at = now()
  WHERE user_id = v_user_id;

  RETURN json_build_object(
    'success', true,
    'equipped_sticker_id', null
  );
END;
$$;

GRANT EXECUTE ON FUNCTION unequip_sticker() TO authenticated;

-- ── 6. 인덱스 ──
CREATE INDEX IF NOT EXISTS idx_user_equipment_sticker
ON public.user_equipment (equipped_sticker_id)
WHERE equipped_sticker_id IS NOT NULL;
