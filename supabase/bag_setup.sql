-- ============================================
-- 내 가방 / 프레임 장착 시스템 DB 설정
-- 작성일: 2026-06-21
-- ============================================

-- ── 1. shop_items에 style_key 컬럼 추가 ─────
--  CSS 프레임 클래스 등 프론트 렌더링 키 저장
--  예: 'frame-mint', 'frame-orange'
ALTER TABLE public.shop_items
ADD COLUMN IF NOT EXISTS style_key text;


-- ── 2. user_profiles에 equipped_frame_id 추가 ─
--  현재 장착 중인 프레임 (NULL = 미착용)
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS equipped_frame_id uuid
  REFERENCES public.shop_items(id) ON DELETE SET NULL;


-- ── 3. user_profiles RLS 정책 확인/추가 ──────
--  본인 프로필만 조회·수정 가능
DROP POLICY IF EXISTS "profiles: select own" ON public.user_profiles;
CREATE POLICY "profiles: select own"
  ON public.user_profiles FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "profiles: update own" ON public.user_profiles;
CREATE POLICY "profiles: update own"
  ON public.user_profiles FOR UPDATE
  USING (auth.uid() = user_id);


-- ── 4. equip_frame RPC ───────────────────────
--  프레임 장착 처리
--  - 로그인 확인
--  - 프레임 아이템인지 확인
--  - 보유 여부 확인
--  - user_profiles.equipped_frame_id 업데이트 (UPSERT)
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

  -- user_profiles 업데이트 (없으면 INSERT)
  INSERT INTO public.user_profiles (user_id, equipped_frame_id, updated_at)
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


-- ── 5. 인덱스 ────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_user_profiles_equipped_frame
  ON public.user_profiles (equipped_frame_id)
  WHERE equipped_frame_id IS NOT NULL;
