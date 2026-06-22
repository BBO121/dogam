-- user_equipment 공개 조회 정책 추가
-- 프로필 페이지에서 타인의 프레임/스티커를 표시하기 위해 필요
-- SELECT는 공개, INSERT/UPDATE는 기존 RPC(SECURITY DEFINER)로만 처리

DROP POLICY IF EXISTS "equipment: select public" ON public.user_equipment;
CREATE POLICY "equipment: select public"
  ON public.user_equipment FOR SELECT
  USING (true);
