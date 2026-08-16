-- ============================================================
-- [보강] INSERT 신원 위조 방지 - 1차 배치 (최종)
-- 대상: adoption_applications, adoptions, auction_bids, auction_details
-- 작성일: 2026-08-16
--
-- adoptions: 저장소 재확인 결과 INSERT 경로는 adoption-write.html 한 곳뿐이고
-- (일반유저/종족주 공용), "종족주/어드민 작성" 정책만을 위한 별도 경로 없음.
-- permissive RLS는 OR로 결합되므로 "로그인 유저 분양 등록"이 WITH CHECK(true)인
-- 이상 이 정책은 이미 실효성이 없었음 -> DROP 후 재생성하지 않음.
--
-- adoptions.author 추가 조치: 이 컬럼이 "작성자 분양 삭제" DELETE 정책의
-- 권한 판정(author = JWT nickname)에도 쓰이고 있어, 위조 시 무관한 제3자가
-- 실제 DELETE 권한을 갖게 되는 문제가 있었음. INSERT 시점에 author가
-- 호출자 본인의 실제 닉네임과 일치하도록 강제해서 원천 차단.
--
-- auction_details: 해당 adoption_id의 adoptions.user_id가 호출자 본인일
-- 때만 생성 허용 (일반유저/종족주 모두 adoptions.user_id=본인이라 자연히 커버됨,
-- admin 대리 생성 경로는 코드상 없음 확인됨).
-- ============================================================

-- ---------- adoption_applications ----------
DROP POLICY IF EXISTS "insert auth" ON public.adoption_applications;
CREATE POLICY "insert auth" ON public.adoption_applications
FOR INSERT TO authenticated
WITH CHECK (applicant_id = auth.uid());

-- ---------- adoptions ----------
DROP POLICY IF EXISTS "로그인 유저 분양 등록" ON public.adoptions;
CREATE POLICY "로그인 유저 분양 등록" ON public.adoptions
FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND author = COALESCE(
    NULLIF((auth.jwt() -> 'user_metadata'::text) ->> 'display_name'::text, ''::text),
    (auth.jwt() -> 'user_metadata'::text) ->> 'nickname'::text
  )
);

DROP POLICY IF EXISTS "종족주/어드민 작성" ON public.adoptions;
-- 재생성하지 않음 (위 정책 하나로 정상 흐름 전체 커버, 별도 경로 없음 재확인됨)

-- ---------- auction_bids ----------
DROP POLICY IF EXISTS "로그인 유저 입찰" ON public.auction_bids;
CREATE POLICY "로그인 유저 입찰" ON public.auction_bids
FOR INSERT TO authenticated
WITH CHECK (bidder_id = auth.uid());

-- ---------- auction_details ----------
DROP POLICY IF EXISTS "종족주/어드민 경매상세 작성" ON public.auction_details;
CREATE POLICY "종족주/어드민 경매상세 작성" ON public.auction_details
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.adoptions
    WHERE adoptions.id = auction_details.adoption_id
      AND adoptions.user_id = auth.uid()
  )
);
