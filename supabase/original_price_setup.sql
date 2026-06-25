-- ============================================
-- shop_items 정가(original_price) 컬럼 추가
-- 작성일: 2026-06-25
-- ============================================

-- ── 1. 컬럼 추가 ─────────────────────────────
ALTER TABLE public.shop_items
ADD COLUMN IF NOT EXISTS original_price integer;

-- ── 2. 일러스트·한정 프레임 정가 설정 ──────────
-- frame_ai_add.sql로 등록한 8종 (정가 100 → 할인가 80)
UPDATE public.shop_items
SET original_price = 100
WHERE style_key IN (
  'frame-ai-dino',
  'frame-ai-night',
  'frame-ai-ocean',
  'frame-ai-whitecat',
  'frame-ai-blackcat',
  'frame-ai-fishcat',
  'frame-ai-siamcat',
  'frame-li-bbo'
);
