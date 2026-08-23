-- ============================================================
-- [기능] 이벤트 경매 최상단 고정 + 입찰 시작 시각(bid_open_at)
-- 작성일: 2026-08-23
--
-- 목적
--   1) 특정 경매(adoption_type='auction')를 "이벤트 경매"로 지정해
--      분양 목록/메인 페이지 최상단에 항상 고정 노출한다.
--      (프론트: pages/adoption.html, pages/index.html)
--   2) 경매에 "입찰 시작 시각"을 지정해, 게시는 미리 해두고 실제
--      입찰(제시)은 지정 시각부터만 가능하게 한다. 향후 일반 경매에도
--      재사용 가능한 공통 필드로 설계하되, 현재 등록 UI는 admin 화면
--      (pages/adoption-write.html, admin 로그인 시에만 필드 노출)에만
--      우선 적용한다.
--
-- 기존 데이터 호환:
--   is_featured_event DEFAULT false, bid_open_at DEFAULT NULL 로 추가되므로
--   기존에 등록된 모든 분양/경매는 컬럼 추가 즉시 기존과 100% 동일하게
--   동작한다 (최상단 고정 없음 / 입찰 즉시 가능).
--
-- [조사 결과 — INSERT/UPDATE 경로]
--   adoptions INSERT는 pages/adoption-write.html 한 곳뿐(일반유저/종족주 공용,
--   is_featured_event를 아예 보내지 않음). 그러나 RLS WITH CHECK는 컬럼
--   값까지는 보지 않으므로, 브라우저 콘솔에서
--   sb.from('adoptions').insert({..., is_featured_event:true})를 직접
--   호출하면 RLS만으로는 막히지 않는다. adoptions에 대한 UPDATE 경로도
--   pages/adoption-detail.html 여러 곳(작성자 낙찰 확정, 즉분 입찰 등)에서
--   직접 .update()를 호출하고 있어 동일한 우회 위험이 있다.
--   -> INSERT/UPDATE 모두 DB 레벨 가드가 필요하다.
--   (선례: supabase/character_special_badge_setup.sql과 동일한 패턴)
--
-- [권한 판정]
--   auth.jwt() -> 'app_metadata' ->> 'role' = 'admin' 브라우저 요청만
--   is_featured_event를 true로 설정/변경 가능. auth.uid() IS NULL인
--   요청(Supabase SQL Editor, 서비스 롤 스크립트 등 운영자 직접 실행)은
--   기존 의도대로 항상 허용한다.
--
-- [입찰 시작 시각 차단]
--   실제 입찰은 pages/adoption-detail.html의 submitBid()에서
--   sb.from('auction_bids').insert(...)로 직접 처리된다(RPC 아님).
--   따라서 프론트 UI만 막으면 콘솔/API 직접 호출로 우회 가능 —
--   auction_bids INSERT에 BEFORE 트리거를 걸어 now() < bid_open_at이면
--   무조건 거부한다.
-- ============================================================


-- ================================================================
-- 1. adoptions.is_featured_event
-- ================================================================

ALTER TABLE public.adoptions
ADD COLUMN IF NOT EXISTS is_featured_event boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.adoptions.is_featured_event IS
'운영자(admin) 전용 이벤트 경매 고정 플래그. true면 분양 목록/메인 페이지 최상단에 일반 등록 순서와 무관하게 항상 고정 노출된다. adoption_type=''auction''에만 허용(adoptions_featured_event_requires_auction 제약 + 트리거로 이중 검증). INSERT/UPDATE 모두 trg_guard_adoptions_featured_event_* 트리거로 admin 브라우저 요청 또는 JWT 없는 운영 DB 실행만 허용된다.';

-- 이벤트 지정은 경매 타입에만 허용 (테이블 제약으로도 이중 방어)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'adoptions_featured_event_requires_auction'
  ) THEN
    ALTER TABLE public.adoptions
      ADD CONSTRAINT adoptions_featured_event_requires_auction
      CHECK (NOT is_featured_event OR adoption_type = 'auction');
  END IF;
END $$;

-- 이벤트 경매 조회용 부분 인덱스 (분양 목록/메인 최상단 렌더링에 사용)
CREATE INDEX IF NOT EXISTS idx_adoptions_is_featured_event
ON public.adoptions (created_at DESC)
WHERE is_featured_event;


-- ── 변경 가드 함수 — INSERT/UPDATE 공용 ─────────────────────
CREATE OR REPLACE FUNCTION public.guard_adoptions_featured_event()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_caller_role text;
BEGIN
  -- JWT 없는 요청(Supabase SQL Editor, 서비스 롤 스크립트 등 운영자 직접
  -- 실행)은 그대로 통과시킨다.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- 타입 제약은 admin 여부와 무관하게 항상 검증한다.
  IF NEW.is_featured_event AND NEW.adoption_type IS DISTINCT FROM 'auction' THEN
    RAISE EXCEPTION '이벤트 경매 지정은 경매(auction) 타입에만 가능합니다.';
  END IF;

  v_caller_role := (auth.jwt() -> 'app_metadata'::text) ->> 'role'::text;

  -- admin 브라우저 요청은 항상 허용
  IF v_caller_role = 'admin' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.is_featured_event THEN
      RAISE EXCEPTION '이벤트 경매 지정은 관리자만 할 수 있습니다.';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.is_featured_event IS DISTINCT FROM OLD.is_featured_event THEN
      RAISE EXCEPTION '이벤트 경매 지정은 관리자만 변경할 수 있습니다.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_adoptions_featured_event() FROM PUBLIC;


-- INSERT 가드 — is_featured_event를 true로 보내는 시도에만 발동.
-- 이 값을 아예 보내지 않는 절대다수의 정상 등록(adoption-write.html)은
-- 트리거 자체가 실행되지 않는다.
DROP TRIGGER IF EXISTS trg_guard_adoptions_featured_event_insert ON public.adoptions;

CREATE TRIGGER trg_guard_adoptions_featured_event_insert
BEFORE INSERT ON public.adoptions
FOR EACH ROW
WHEN (NEW.is_featured_event)
EXECUTE FUNCTION public.guard_adoptions_featured_event();


-- UPDATE 가드 — is_featured_event 또는 adoption_type이 바뀌는 UPDATE 중,
-- 결과적으로 is_featured_event=true가 되는 경우에만 발동. 이 값을 건드리지
-- 않는 기존 모든 수정 경로(낙찰 확정, 즉분 처리, 마감 등)는 영향 없다.
DROP TRIGGER IF EXISTS trg_guard_adoptions_featured_event_update ON public.adoptions;

CREATE TRIGGER trg_guard_adoptions_featured_event_update
BEFORE UPDATE OF is_featured_event, adoption_type ON public.adoptions
FOR EACH ROW
WHEN (NEW.is_featured_event)
EXECUTE FUNCTION public.guard_adoptions_featured_event();


-- ================================================================
-- 2. auction_details.bid_open_at
-- ================================================================

ALTER TABLE public.auction_details
ADD COLUMN IF NOT EXISTS bid_open_at timestamptz;

COMMENT ON COLUMN public.auction_details.bid_open_at IS
'경매 입찰 시작 시각(선택, 공통 경매 기능 — 이벤트 경매 전용 아님). NULL이면 게시 즉시 입찰 가능(기존 동작과 100% 동일). 값이 있으면 해당 시각 이전 auction_bids INSERT는 trg_guard_auction_bids_bid_open_at 트리거가 서버 측에서 거부한다. 현재 등록 UI는 admin 화면(pages/adoption-write.html)에만 입력 필드를 노출한다.';

-- 입찰 시작 시각은 경매 종료 시각(날짜 지정 마감인 경우)보다 앞서야 한다.
-- close_method='last_bid'(마지막 입찰 후 N시간 마감)는 고정 종료 시각이
-- 없으므로 이 제약 대상이 아니다.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'auction_details_bid_open_before_close'
  ) THEN
    ALTER TABLE public.auction_details
      ADD CONSTRAINT auction_details_bid_open_before_close
      CHECK (
        bid_open_at IS NULL
        OR close_method IS DISTINCT FROM 'date'
        OR close_at IS NULL
        OR bid_open_at < close_at::timestamptz
      );
  END IF;
END $$;


-- ── 입찰 차단 가드 함수 ──────────────────────────────────────
-- auction_bids는 RPC 없이 pages/adoption-detail.html의 submitBid()에서
-- sb.from('auction_bids').insert(...)로 직접 처리되므로, 프론트 UI 비활성화와
-- 무관하게 DB 레벨에서 항상 검증해야 브라우저 콘솔/API 직접 호출도 막힌다.
CREATE OR REPLACE FUNCTION public.guard_auction_bids_open_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_bid_open_at timestamptz;
BEGIN
  -- JWT 없는 요청(운영자 직접 실행)은 통과
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT bid_open_at INTO v_bid_open_at
  FROM public.auction_details
  WHERE adoption_id = NEW.adoption_id;

  IF v_bid_open_at IS NOT NULL AND now() < v_bid_open_at THEN
    RAISE EXCEPTION '아직 입찰 시작 시간이 아닙니다.';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_auction_bids_open_at() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_guard_auction_bids_open_at ON public.auction_bids;

CREATE TRIGGER trg_guard_auction_bids_open_at
BEFORE INSERT ON public.auction_bids
FOR EACH ROW
EXECUTE FUNCTION public.guard_auction_bids_open_at();


-- ================================================================
-- 3. 적용 확인
-- ================================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'adoptions' AND column_name = 'is_featured_event')
    OR (table_name = 'auction_details' AND column_name = 'bid_open_at'));

SELECT tgname, tgrelid::regclass, tgenabled
FROM pg_catalog.pg_trigger
WHERE tgname IN (
  'trg_guard_adoptions_featured_event_insert',
  'trg_guard_adoptions_featured_event_update',
  'trg_guard_auction_bids_open_at'
);


-- ============================================================
-- 사용 예시 (운영자가 Supabase SQL Editor에서 직접 실행 — JWT 없음, 항상 허용)
-- ============================================================
-- 이벤트 경매로 지정:
--   UPDATE public.adoptions SET is_featured_event = true WHERE id = 1234;
--
-- 이벤트 경매 해제:
--   UPDATE public.adoptions SET is_featured_event = false WHERE id = 1234;
--
-- 입찰 시작 시각 지정 (KST 기준 예: 2026-08-25 20:00):
--   UPDATE public.auction_details SET bid_open_at = '2026-08-25 20:00+09'
--   WHERE adoption_id = 1234;
--
-- 입찰 시작 시각 해제(즉시 입찰 가능으로 되돌리기):
--   UPDATE public.auction_details SET bid_open_at = NULL WHERE adoption_id = 1234;
