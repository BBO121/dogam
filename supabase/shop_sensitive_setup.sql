-- ============================================
-- 상점 "민감한 요소" 표시 시스템
-- 작성일: 2026-08-04
-- ============================================

-- ── 1. is_sensitive 컬럼 추가 ─────────────────
ALTER TABLE public.shop_items
  ADD COLUMN IF NOT EXISTS is_sensitive boolean NOT NULL DEFAULT false;

-- ── 2. 기존 민감 아이템 표시 ───────────────────
-- 메어나이트 종족 프레임 + 메어나이트1/2 스티커
UPDATE public.shop_items
SET is_sensitive = true
WHERE style_key IN (
  'frame-sp-marenight',
  'sticker-sp-marenight1',
  'sticker-sp-marenight2'
);
