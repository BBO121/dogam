-- ============================================================
-- [SECURITY] 문의(inquiries) 운영 기록 보존 강화
-- 작성일: 2026-08-17
-- 배경: 문의/답변/댓글은 운영 정책 안내, 이용자 확인/동의, 분쟁 대응에 쓰이는
--       운영 기록이므로 일반 사용자가 임의로 삭제/변조하지 못해야 한다.
--
-- 확인된 기존 문제 (뽀가 라이브 pg_policies에서 직접 확인):
--   1) "문의 삭제" DELETE 정책이 답변/댓글 유무를 전혀 보지 않아, 관리자가 답변한
--      문의도 작성자 본인이 DELETE로 지울 수 있었음 (프론트는 UI에서만 막고 있었음).
--   2) "allow_own_reply_on_inquiries" UPDATE 정책이
--         USING (auth.uid() = user_id)  WITH CHECK (auth.uid() = user_id)
--      뿐이라 컬럼 제한이 전혀 없음 — comments(jsonb 배열) 전체 덮어쓰기, 즉
--      관리자 댓글 삭제/변조, answer/answered_by/answered_at/status 직접 변경이
--      전부 가능한 구조였음 (프론트는 자기 댓글만 건드리게 그려줬을 뿐, API를
--      직접 호출하면 우회 가능).
--
-- 이번 패치의 방향:
--   - "문의 삭제": 소유권 기준을 nickname → user_id로 변경 + 답변/댓글/상태 변경이
--     하나도 없는("아직 아무도 손대지 않은") 본인 문의만 삭제 가능하도록 조건 추가.
--     admin은 기존처럼 무조건 삭제 가능. staff는 기존과 동일하게 DELETE 권한 없음
--     (신규 부여하지 않음).
--   - "allow_own_reply_on_inquiries"는 완전히 삭제한다. 답변/댓글 추가는
--     add_inquiry_comment() RPC(SECURITY DEFINER)로만 가능하게 하여, comments
--     배열은 append-only, answer/answered_by/answered_at/status는 admin일 때만
--     RPC 내부 로직으로 갱신되도록 강제한다. RLS만으로는 jsonb 배열 안의 "내 댓글만"
--     같은 요소 단위 보호가 불가능하므로 RPC 방식을 사용.
--   - "문의 조회"(SELECT), "문의 수정"(admin 전용 UPDATE, staff 미포함), "문의 삽입"(INSERT)
--     은 변경하지 않는다 (요청 범위 밖 + staff 권한을 임의로 넓히지 않기 위함).
--
-- 스키마 변경 없음 (컬럼 추가/삭제 없음), 기존 데이터(answer/comments/user_reply 등)
-- 는 전혀 건드리지 않는다.
-- ============================================================

-- ---------- 0. 사전 확인(선택) ----------
-- comments 컬럼이 jsonb인지 미리 확인하고 싶다면 아래를 먼저 실행해 결과를 봐주세요.
-- data_type이 'jsonb'가 아니라면(예: 'json') 알려주시면 패치를 조정하겠습니다.
--
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'inquiries'
--   AND column_name IN ('comments', 'answer', 'answered_by', 'answered_at', 'status', 'user_id');


-- ---------- 1. 문의 삭제 (DELETE) ----------
-- 본인 문의라도 답변(answer)/댓글(comments)이 하나라도 있거나 상태가 "접수됨"이
-- 아니면(=운영진이 이미 손을 댔으면) 삭제 불가. admin은 예외 없이 항상 삭제 가능.
-- 소유권 판정은 nickname 문자열 비교 대신 user_id로 변경.
DROP POLICY IF EXISTS "문의 삭제" ON public.inquiries;

CREATE POLICY "문의 삭제" ON public.inquiries
FOR DELETE
USING (
  (
    auth.uid() = user_id
    AND answer IS NULL
    AND (comments IS NULL OR jsonb_array_length(comments::jsonb) = 0)
    AND (status IS NULL OR status = '접수됨')
  )
  OR ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text
);


-- ---------- 2. allow_own_reply_on_inquiries 삭제 ----------
-- 기존: USING (auth.uid() = user_id)  WITH CHECK (auth.uid() = user_id) — 컬럼 제한 없이
-- 본인 문의 행 전체를 UPDATE 가능했던 정책. 삭제 후에는 일반 사용자가 inquiries 테이블에
-- 대해 사용할 수 있는 UPDATE 경로가 전혀 남지 않는다(아래 RPC를 통해서만 기록 추가 가능).
DROP POLICY IF EXISTS "allow_own_reply_on_inquiries" ON public.inquiries;

-- 참고 — 아래 정책들은 이번 패치에서 변경하지 않음(그대로 유지):
--   - "문의 조회" (SELECT, auth.uid() = user_id OR app_metadata.role IN (admin, staff))
--   - "문의 수정" (UPDATE, app_metadata.role = 'admin' 전용 — staff 미포함, 기존 설계 유지)
--   - "문의 삽입" (INSERT)


-- ---------- 3. add_inquiry_comment() RPC ----------
-- 문의에 새 회신/댓글 1개를 append하는 유일한 통로.
--   - 호출자가 문의 소유자(auth.uid() = user_id) 또는 app_metadata.role = 'admin'
--     이 아니면 예외를 던진다 (staff는 "문의 수정"과 동일하게 대상에서 제외).
--   - comments 배열은 항상 "기존 배열 + 새 항목 1개"로만 갱신된다 — 기존 항목을
--     지우거나 바꾸는 경로 자체가 없다.
--   - author/author_user_id/is_admin/role은 클라이언트가 보낸 값이 아니라 서버가
--     auth.uid()/auth.jwt()/auth.users에서 직접 조회해 채운다 (작성자 사칭 방지).
--   - status/answer/answered_by/answered_at은 호출자가 실제 admin일 때만 갱신된다.
--     (answer/answered_by/answered_at은 최초 1회만 세팅 — 기존 프론트 로직과 동일)
--   - SECURITY DEFINER로 실행되어 RLS를 우회하지만, 함수 내부에서 위 권한 검사를
--     직접 수행하므로 안전하다. search_path를 비워 스키마 하이재킹을 방지하고
--     public./auth. 스키마를 전부 명시적으로 지정한다.
CREATE OR REPLACE FUNCTION public.add_inquiry_comment(
  p_inquiry_id uuid,
  p_content text,
  p_status text DEFAULT NULL
)
RETURNS public.inquiries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_role    text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_row     public.inquiries%ROWTYPE;
  v_is_admin boolean;
  v_nickname text;
  v_new_comment jsonb;
  v_result  public.inquiries;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RAISE EXCEPTION '내용을 입력해주세요.';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('접수됨', '처리중', '완료') THEN
    RAISE EXCEPTION '잘못된 상태값입니다.';
  END IF;

  SELECT * INTO v_row FROM public.inquiries WHERE id = p_inquiry_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION '문의를 찾을 수 없습니다.';
  END IF;

  v_is_admin := (v_role = 'admin');

  IF NOT (v_is_admin OR v_row.user_id = v_uid) THEN
    RAISE EXCEPTION '권한이 없습니다.';
  END IF;

  SELECT COALESCE(
    NULLIF(raw_user_meta_data ->> 'display_name', ''),
    raw_user_meta_data ->> 'nickname'
  ) INTO v_nickname
  FROM auth.users WHERE id = v_uid;

  v_new_comment := jsonb_build_object(
    'author',          COALESCE(v_nickname, '알 수 없음'),
    'author_user_id',  v_uid,
    'is_admin',        v_is_admin,
    'role',            CASE WHEN v_is_admin THEN v_role ELSE NULL END,
    'content',         p_content,
    'created_at',      now()
  );

  UPDATE public.inquiries
  SET
    comments    = COALESCE(comments, '[]'::jsonb) || jsonb_build_array(v_new_comment),
    status      = CASE WHEN v_is_admin AND p_status IS NOT NULL THEN p_status ELSE status END,
    answer      = CASE WHEN v_is_admin AND answer IS NULL THEN p_content ELSE answer END,
    answered_by = CASE WHEN v_is_admin AND answer IS NULL THEN COALESCE(v_nickname, '관리자') ELSE answered_by END,
    answered_at = CASE WHEN v_is_admin AND answer IS NULL THEN now() ELSE answered_at END
  WHERE id = p_inquiry_id
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.add_inquiry_comment(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_inquiry_comment(uuid, text, text) TO authenticated;
