-- ============================================================
-- [기능] 경매 사용 재화(원/연구기록) 선택 기능
-- 작성일: 2026-08-21
--
-- auction_details 테이블에 경매 사용 재화 컬럼 추가.
-- 경매 로직/계산 방식은 변경 없음 — 표시/저장되는 단위만 구분함.
--
-- 기존 데이터 호환: DEFAULT 'krw'로 추가하므로 기존에 등록된 경매
-- 게시글은 컬럼 추가 즉시 전부 'krw'(원)로 채워져 기존과 동일하게 취급됨.
-- ============================================================

ALTER TABLE public.auction_details
  ADD COLUMN IF NOT EXISTS auction_currency text NOT NULL DEFAULT 'krw';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'auction_details_auction_currency_check'
  ) THEN
    ALTER TABLE public.auction_details
      ADD CONSTRAINT auction_details_auction_currency_check
      CHECK (auction_currency IN ('krw', 'research_records'));
  END IF;
END $$;
