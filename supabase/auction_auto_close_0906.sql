-- ============================================================
-- [기능] 경매형 분양 자동 마감 — effective close 계산 + 마감 후 입찰 서버 차단
-- 작성일: 2026-09-06
--
-- 목적
--   기존 두 마감 방식(close_method = 'date' / 'last_bid')이 실제로
--   "마감시간 도달 → 추가 입찰 차단"으로 동작하도록 완성한다.
--   - 새 컬럼/새 status 값을 만들지 않는다.
--   - 낙찰자 결정은 기존 auction_bids 최고가 로직을 그대로 사용(프론트).
--   - 재화 자동 차감/지급/정산/자동 소유권 이전은 전혀 하지 않는다.
--     (마감 시스템은 "종료 판정 + 입찰 차단"까지만 담당)
--
-- 종료시각 규칙 (public.auction_effective_close_at)
--   close_method = 'date'
--     → close_at 그대로 반환 (timestamptz = 절대시각, AT TIME ZONE 변환 없음)
--   close_method = 'last_bid' (close_hours > 0)
--     → max(auction_bids.created_at) + make_interval(hours => close_hours)
--       입찰 0건이면 max()=NULL → 함수 결과 NULL (첫 입찰 전에는 마감 안 됨)
--   그 외 / 설정 없음
--     → NULL (종료 제한 없음 = 기존 데이터 100% 호환)
--
-- 서버 입찰 차단 (auction_bids BEFORE INSERT)
--   v_end := auction_effective_close_at(NEW.adoption_id);
--   IF v_end IS NOT NULL AND now() >= v_end THEN RAISE EXCEPTION '이미 마감된 경매입니다.';
--   - now() 기준 판정 → 클라이언트 PC 시계가 틀려도 영향 없음.
--   - v_end IS NULL → 통과 (종료시각 없는 경매는 지금처럼 계속 입찰 가능).
--   - 기존 trg_guard_auction_bids_open_at(입찰 시작 시각 차단)와 독립.
--     BEFORE ROW 트리거는 이름 알파벳순 실행: closed → open_at. 둘 다
--     "거부 아니면 통과"라 순서 무관.
--
-- 기존 close_at 데이터
--   이 스크립트는 close_at 값을 절대 수정하지 않는다. (마이그레이션 없음)
--   과거 등록분은 adoption-write.html의 close_at 저장 버그(datetime-local
--   원본 문자열을 그대로 INSERT → UTC로 해석되어 +9h)로 인해 의도보다
--   9시간 늦게 저장됐을 수 있으나, 등록자가 화면 표시에 맞춰 수동 보정했을
--   가능성도 있어 일괄 보정하지 않는다. 신규 등록분부터 프론트에서 정상화.
--   → 하단 "검사용 SELECT"로 영향 범위만 확인.
-- ============================================================


-- ================================================================
-- 0. 선행 확인 (참고용 — 실행해도 부작용 없음)
-- ================================================================
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('auction_details', 'auction_bids')
  AND column_name IN ('close_method', 'close_at', 'close_hours', 'bid_open_at', 'created_at', 'adoption_id')
ORDER BY table_name, column_name;
-- 기대: auction_details.close_at = timestamp with time zone


-- ================================================================
-- 1. effective close 계산 함수
-- ================================================================
-- SECURITY DEFINER: 마감 판정의 원천이므로 auction_bids/auction_details의
-- 향후 RLS 변경(예: "본인 입찰만 조회")에 영향받지 않고 항상 전체 입찰을 본다.
CREATE OR REPLACE FUNCTION public.auction_effective_close_at(p_adoption_id bigint)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT CASE
    WHEN ad.close_method = 'date' THEN
      ad.close_at
    WHEN ad.close_method = 'last_bid' AND ad.close_hours IS NOT NULL AND ad.close_hours > 0 THEN
      (
        SELECT max(b.created_at) + make_interval(hours => ad.close_hours::int)
        FROM public.auction_bids b
        WHERE b.adoption_id = p_adoption_id
      )
    ELSE
      NULL
  END
  FROM public.auction_details ad
  WHERE ad.adoption_id = p_adoption_id;
$$;

COMMENT ON FUNCTION public.auction_effective_close_at(bigint) IS
'경매(adoption_type=''auction'')의 실제 종료시각(timestamptz)을 계산한다. close_method=''date''면 close_at 그대로, ''last_bid''면 마지막 입찰(auction_bids.created_at 최댓값) + close_hours시간. 입찰 0건이거나 마감 설정이 없으면 NULL(종료 제한 없음). now()와 직접 비교해 마감 여부를 판정한다.';

-- guard 트리거 함수(SECURITY INVOKER)가 이 함수를 호출하므로 authenticated에 EXECUTE 필요.
-- 반환값은 경매 종료시각 하나뿐 — 이미 사이트에 공개된 정보라 노출 위험 없음.
REVOKE ALL ON FUNCTION public.auction_effective_close_at(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auction_effective_close_at(bigint) TO authenticated;


-- 조회 성능용 인덱스 (last_bid 방식의 max(created_at) 계산 / 목록 조회 공통)
CREATE INDEX IF NOT EXISTS idx_auction_bids_adoption_created
ON public.auction_bids (adoption_id, created_at DESC);


-- ================================================================
-- 2. 마감 후 입찰 차단 트리거
-- ================================================================
CREATE OR REPLACE FUNCTION public.guard_auction_bids_closed()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_end timestamptz;
BEGIN
  -- JWT 없는 요청(Supabase SQL Editor, 서비스 롤 스크립트 등 운영자 직접
  -- 실행)은 그대로 통과 — 기존 guard_auction_bids_open_at와 동일 패턴.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_end := public.auction_effective_close_at(NEW.adoption_id);

  IF v_end IS NOT NULL AND now() >= v_end THEN
    RAISE EXCEPTION '이미 마감된 경매입니다.';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_auction_bids_closed() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_guard_auction_bids_closed ON public.auction_bids;

CREATE TRIGGER trg_guard_auction_bids_closed
BEFORE INSERT ON public.auction_bids
FOR EACH ROW
EXECUTE FUNCTION public.guard_auction_bids_closed();


-- ================================================================
-- 3. 적용 확인
-- ================================================================
SELECT tgname, tgrelid::regclass, tgenabled
FROM pg_catalog.pg_trigger
WHERE tgname IN ('trg_guard_auction_bids_closed', 'trg_guard_auction_bids_open_at')
ORDER BY tgname;

-- date 경매 하나로 함수 동작 확인 (adoption_id는 상황에 맞게 교체)
-- SELECT adoption_id, close_method, close_at, close_hours,
--        public.auction_effective_close_at(adoption_id) AS effective_close,
--        now() >= public.auction_effective_close_at(adoption_id) AS 마감됨
-- FROM public.auction_details
-- ORDER BY adoption_id DESC LIMIT 20;


-- ================================================================
-- 4. 검사용 SELECT — 기존 close_at 9시간 오차 영향 범위 (조회만, 수정 없음)
-- ================================================================
-- "현재해석"(그대로) vs "9시간 뺀 가정" 중 어느 쪽이 등록자 의도에 맞는지
-- 뽀가 눈으로 판단 → 이후 개별 보정 여부를 별도로 결정.
SELECT
  ad.adoption_id,
  a.status,
  a.created_at AT TIME ZONE 'Asia/Seoul'                          AS 등록_kst,
  ad.close_at                                                     AS close_at_저장값_utc,
  ad.close_at AT TIME ZONE 'Asia/Seoul'                           AS close_at_kst_현재해석,
  (ad.close_at - interval '9 hours') AT TIME ZONE 'Asia/Seoul'    AS close_at_kst_9시간뺀가정,
  (ad.close_at <= now())                                          AS 이미_지났나_현재해석,
  (SELECT count(*) FROM public.auction_bids b WHERE b.adoption_id = ad.adoption_id) AS 입찰수
FROM public.auction_details ad
JOIN public.adoptions a ON a.id = ad.adoption_id
WHERE ad.close_method = 'date'
  AND ad.close_at IS NOT NULL
ORDER BY a.created_at DESC;

-- ⚠ 기존 close_at 데이터를 일괄 +9h / -9h 하는 UPDATE는 실행하지 말 것.
