-- 디자인권 소유주가 사용 요청/취소할 수 있도록 UPDATE 정책 추가
-- WITH CHECK: status가 active인 경우만 허용 (used 상태 소유주 수정 방지)

CREATE POLICY "slots_update_owner_request"
  ON public.slots FOR UPDATE
  USING  (slots.owner_user_id = auth.uid())
  WITH CHECK (
    slots.owner_user_id = auth.uid()
    AND slots.status = 'active'
  );
