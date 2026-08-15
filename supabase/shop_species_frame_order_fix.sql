-- ============================================
-- 종족 프레임 7종 진열 순서 고정
-- 매어나이트 → 테일스 → 옥토몬스터 → 쁘띠아라크네 → 뜨개뽀기 → 비홀로틀 → 버블리
--
-- 배경: frame_category_order_fix.sql에서 "frame + 종족" 카테고리 전체를
-- sort_order=170으로 일괄 고정해뒀기 때문에, 같은 sort_order를 가진 종족
-- 프레임끼리는 created_at(생성 시각) 순서로 정렬되어 실제 노출 순서를
-- 보장할 수 없었음. 종족 프레임 7종에 서로 다른 sort_order를 부여해
-- 순서를 명시적으로 고정함.
--
-- 스티커(종족)는 이미 150/160(매어나이트) → 170/180(테일스) →
-- 190~230(옥토몬스터~버블리)로 전부 다른 값이 부여되어 있어 별도 조치 불필요.
--
-- shop_species_5set_add_0815.sql을 아직 실행하지 않았다면 이 UPDATE는
-- 옥토몬스터/쁘띠아라크네/뜨개뽀기/비홀로틀/버블리 프레임에 대해
-- 대상이 없어 영향 없음 (해당 INSERT 파일에는 이미 172~176으로 반영해둠).
-- 이미 실행했다면 이 UPDATE로 순서가 고정됨.
-- 작성일: 2026-08-15
-- ============================================

UPDATE public.shop_items SET sort_order = 170 WHERE style_key = 'frame-sp-marenight';
UPDATE public.shop_items SET sort_order = 171 WHERE style_key = 'frame-sp-tails';
UPDATE public.shop_items SET sort_order = 172 WHERE style_key = 'frame-sp-octomonster';
UPDATE public.shop_items SET sort_order = 173 WHERE style_key = 'frame-sp-petitarachne';
UPDATE public.shop_items SET sort_order = 174 WHERE style_key = 'frame-sp-bbogi';
UPDATE public.shop_items SET sort_order = 175 WHERE style_key = 'frame-sp-bexolotl';
UPDATE public.shop_items SET sort_order = 176 WHERE style_key = 'frame-sp-bubblere';
