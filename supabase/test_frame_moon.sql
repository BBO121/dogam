-- ============================================
-- 테스트용 프레임 추가
-- 작성일: 2026-06-23
-- 목적: 상점 노출 및 구매 UI 정상 동작 확인
-- 비고: 테스트 완료 후 삭제 예정
-- ============================================

INSERT INTO public.shop_items
  (item_type, name, description, currency, price, status, image_url, style_key, sub_category, sort_order)
VALUES
(
  'frame', '테스트용', '상점 구매 테스트용 프레임',
  'research_records', 1000, 'active',
  '../images/shop/frame_ai_moon.png', NULL,
  '테스트', 999
);

-- 삭제 시:
-- DELETE FROM public.shop_items WHERE name = '테스트용' AND sub_category = '테스트';
