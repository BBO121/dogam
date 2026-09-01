-- ============================================================
-- [FEATURE/SECURITY] 문의 회신(댓글) 운영진 수정/삭제 복구 + 문의 삭제 staff 허용
-- 작성일: 2026-09-01
--
-- 목적
--   - 일반 유저의 문의 회신 append-only 정책은 그대로 유지
--   - admin / staff 만 회신 수정·삭제 가능
--   - admin / staff 모두 문의 전체 삭제 가능
--   - 권한 판정은 auth.jwt() -> app_metadata.role 기준
--
-- 주요 보완
--   1) 기존 comments 원소에 UUID id 백필
--      - id 없음: 새 UUID 부여
--      - id가 있지만 UUID 형식이 아님: 새 UUID로 교체
--   2) 레거시 is_admin 값은 boolean cast 하지 않고 문자열 'true'로 비교
--      → 비정상 레거시 값 때문에 RPC 전체가 실패하는 문제 방지
--   3) answer / answered_by / answered_at 미러 필드 동기화 보강
--   4) 레거시 created_at이 비정상이어도 삭제 RPC 전체가 실패하지 않도록 방어
--   5) 일반 유저 append-only 정책은 완화하지 않음
--
-- 스키마 컬럼 변경 없음.
-- comments JSONB 원소에 id 키를 추가/정상화한다.
-- ============================================================


-- ------------------------------------------------------------
-- 0. 적용 전 확인용 쿼리 (읽기 전용 / 선택)
-- ------------------------------------------------------------

-- comments가 배열이 아닌 문의 확인
-- SELECT id, jsonb_typeof(comments) AS comments_type
-- FROM public.inquiries
-- WHERE comments IS NOT NULL
--   AND jsonb_typeof(comments) <> 'array';

-- is_admin / role 값 분포 확인
-- SELECT
--   elem ->> 'is_admin' AS is_admin_value,
--   elem ->> 'role' AS role_value,
--   count(*)
-- FROM public.inquiries i
-- CROSS JOIN LATERAL jsonb_array_elements(
--   CASE
--     WHEN jsonb_typeof(i.comments) = 'array' THEN i.comments
--     ELSE '[]'::jsonb
--   END
-- ) AS t(elem)
-- GROUP BY 1, 2
-- ORDER BY 3 DESC;

-- created_at 누락/비정상 형태 후보 확인
-- SELECT i.id AS inquiry_id, elem ->> 'created_at' AS created_at_value
-- FROM public.inquiries i
-- CROSS JOIN LATERAL jsonb_array_elements(
--   CASE
--     WHEN jsonb_typeof(i.comments) = 'array' THEN i.comments
--     ELSE '[]'::jsonb
--   END
-- ) AS t(elem)
-- WHERE NOT (elem ? 'created_at')
--    OR (elem ->> 'created_at') !~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}';


-- ------------------------------------------------------------
-- 1. 기존 comments 원소에 안정적 UUID id 백필/정상화
--
-- - 이미 정상 UUID인 id는 유지
-- - id가 없거나 UUID 형식이 아니면 새 UUID 부여
-- - comments가 array가 아닌 레거시 row는 여기서 건드리지 않음
-- ------------------------------------------------------------
UPDATE public.inquiries i
SET comments = sub.new_comments
FROM (
  SELECT
    i2.id AS inquiry_id,
    jsonb_agg(
      CASE
        WHEN (elem ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          THEN elem
        ELSE elem || jsonb_build_object('id', gen_random_uuid())
      END
      ORDER BY ord
    ) AS new_comments
  FROM public.inquiries i2
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(i2.comments) = 'array' THEN i2.comments
      ELSE '[]'::jsonb
    END
  ) WITH ORDINALITY AS t(elem, ord)
  WHERE i2.comments IS NOT NULL
    AND jsonb_typeof(i2.comments) = 'array'
    AND jsonb_array_length(i2.comments) > 0
  GROUP BY i2.id
) AS sub
WHERE i.id = sub.inquiry_id
  AND sub.new_comments IS DISTINCT FROM i.comments;


-- ------------------------------------------------------------
-- 2. add_inquiry_comment()
--
-- 일반 유저:
--   - 자기 문의에 새 댓글 추가만 가능
--   - 기존 댓글 수정/삭제 불가
--
-- 운영진(admin/staff):
--   - 모든 문의에 댓글 추가 가능
--   - 상태 변경 가능
--   - 최초 운영진 댓글은 answer 미러 필드에도 기록
-- ------------------------------------------------------------
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
  v_uid         uuid := auth.uid();
  v_role        text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_row         public.inquiries%ROWTYPE;
  v_is_operator boolean;
  v_nickname    text;
  v_new_comment jsonb;
  v_result      public.inquiries;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RAISE EXCEPTION '내용을 입력해주세요.';
  END IF;

  IF p_status IS NOT NULL
     AND p_status NOT IN ('접수됨', '처리중', '완료') THEN
    RAISE EXCEPTION '잘못된 상태값입니다.';
  END IF;

  SELECT *
  INTO v_row
  FROM public.inquiries
  WHERE id = p_inquiry_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '문의를 찾을 수 없습니다.';
  END IF;

  -- 비정상 레거시 데이터가 있으면 조용히 덮어쓰지 않고 중단
  IF v_row.comments IS NOT NULL
     AND jsonb_typeof(v_row.comments) <> 'array' THEN
    RAISE EXCEPTION '문의 회신 데이터 형식이 올바르지 않습니다.';
  END IF;

  v_is_operator := (v_role IN ('admin', 'staff'));

  IF NOT (v_is_operator OR v_row.user_id = v_uid) THEN
    RAISE EXCEPTION '권한이 없습니다.';
  END IF;

  SELECT COALESCE(
    NULLIF(raw_user_meta_data ->> 'display_name', ''),
    NULLIF(raw_user_meta_data ->> 'nickname', '')
  )
  INTO v_nickname
  FROM auth.users
  WHERE id = v_uid;

  v_new_comment := jsonb_build_object(
    'id',             gen_random_uuid(),
    'author',         COALESCE(v_nickname, '알 수 없음'),
    'author_user_id', v_uid,
    'is_admin',       v_is_operator,
    'role',           CASE WHEN v_is_operator THEN v_role ELSE NULL END,
    'content',        p_content,
    'created_at',     now()
  );

  UPDATE public.inquiries
  SET
    comments = COALESCE(comments, '[]'::jsonb) || jsonb_build_array(v_new_comment),

    status = CASE
      WHEN v_is_operator AND p_status IS NOT NULL
        THEN p_status
      ELSE status
    END,

    answer = CASE
      WHEN v_is_operator AND answer IS NULL
        THEN p_content
      ELSE answer
    END,

    answered_by = CASE
      WHEN v_is_operator AND answer IS NULL
        THEN COALESCE(v_nickname, '관리자')
      ELSE answered_by
    END,

    answered_at = CASE
      WHEN v_is_operator AND answer IS NULL
        THEN now()
      ELSE answered_at
    END

  WHERE id = p_inquiry_id
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL
ON FUNCTION public.add_inquiry_comment(uuid, text, text)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.add_inquiry_comment(uuid, text, text)
TO authenticated;


-- ------------------------------------------------------------
-- 3. update_inquiry_comment()
-- 운영진(admin/staff) 전용 회신 수정
--
-- answer 동기화 규칙:
--   수정 대상이
--   1) 운영진 댓글이고
--   2) comments 배열에서 최초 운영진 댓글이며
--   3) 현재 answer가 수정 전 content와 일치할 때만
--   answer를 새 content로 동기화
--
-- 동일 문자열의 다른 댓글을 수정해도 answer는 변하지 않음.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_inquiry_comment(
  p_inquiry_id uuid,
  p_comment_id uuid,
  p_content text
)
RETURNS public.inquiries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid           uuid := auth.uid();
  v_role          text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_row           public.inquiries%ROWTYPE;
  v_old_content   text;
  v_target_ord    bigint;
  v_target_is_op  boolean;
  v_first_op_ord  bigint;
  v_is_answer_src boolean;
  v_new_comments  jsonb;
  v_result        public.inquiries;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  IF v_role IS NULL OR v_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '권한이 없습니다. (운영진 전용)';
  END IF;

  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RAISE EXCEPTION '내용을 입력해주세요.';
  END IF;

  SELECT *
  INTO v_row
  FROM public.inquiries
  WHERE id = p_inquiry_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '문의를 찾을 수 없습니다.';
  END IF;

  IF v_row.comments IS NULL
     OR jsonb_typeof(v_row.comments) <> 'array' THEN
    RAISE EXCEPTION '회신을 찾을 수 없습니다.';
  END IF;

  -- 대상 댓글 정보
  SELECT
    t.ord,
    t.elem ->> 'content',
    (
      (t.elem ->> 'is_admin') = 'true'
      OR (t.elem ->> 'role') IN ('admin', 'staff')
    )
  INTO
    v_target_ord,
    v_old_content,
    v_target_is_op
  FROM jsonb_array_elements(v_row.comments)
       WITH ORDINALITY AS t(elem, ord)
  WHERE (t.elem ->> 'id') = p_comment_id::text
  ORDER BY t.ord
  LIMIT 1;

  IF v_target_ord IS NULL THEN
    RAISE EXCEPTION '회신을 찾을 수 없습니다.';
  END IF;

  -- 배열에서 최초 운영진 댓글
  SELECT t.ord
  INTO v_first_op_ord
  FROM jsonb_array_elements(v_row.comments)
       WITH ORDINALITY AS t(elem, ord)
  WHERE
    (t.elem ->> 'is_admin') = 'true'
    OR (t.elem ->> 'role') IN ('admin', 'staff')
  ORDER BY t.ord
  LIMIT 1;

  v_is_answer_src := (
    COALESCE(v_target_is_op, false)
    AND v_first_op_ord IS NOT NULL
    AND v_target_ord = v_first_op_ord
    AND v_row.answer IS NOT NULL
    AND v_old_content IS NOT NULL
    AND v_row.answer = v_old_content
  );

  SELECT jsonb_agg(
    CASE
      WHEN (elem ->> 'id') = p_comment_id::text
        THEN elem || jsonb_build_object(
          'content', p_content,
          'updated_at', now()
        )
      ELSE elem
    END
    ORDER BY ord
  )
  INTO v_new_comments
  FROM jsonb_array_elements(v_row.comments)
       WITH ORDINALITY AS t(elem, ord);

  UPDATE public.inquiries
  SET
    comments = v_new_comments,
    answer = CASE
      WHEN v_is_answer_src THEN p_content
      ELSE answer
    END
  WHERE id = p_inquiry_id
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL
ON FUNCTION public.update_inquiry_comment(uuid, uuid, text)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.update_inquiry_comment(uuid, uuid, text)
TO authenticated;


-- ------------------------------------------------------------
-- 4. delete_inquiry_comment()
-- 운영진(admin/staff) 전용 회신 삭제
--
-- answer 동기화 규칙:
--   - 삭제 대상이 최초 운영진 댓글이면
--       남은 최초 운영진 댓글로 answer 3필드 재동기화
--   - 남은 운영진 댓글이 없으면 answer 3필드 NULL
--   - 삭제 대상이 answer 원본이 아니면 기존 answer 유지
--
-- 레거시 created_at 방어:
--   - 정상 timestamp면 원래 created_at 사용
--   - 누락/비정상 값이면 now() 사용
--     (RPC 전체 실패보다 운영 기능 유지 우선)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_inquiry_comment(
  p_inquiry_id uuid,
  p_comment_id uuid
)
RETURNS public.inquiries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid           uuid := auth.uid();
  v_role          text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_row           public.inquiries%ROWTYPE;

  v_del_ord       bigint;
  v_del_is_op     boolean;
  v_first_op_ord  bigint;
  v_is_answer_src boolean;

  v_new_comments  jsonb;
  v_new_len       integer;

  v_next_content  text;
  v_next_author   text;
  v_next_at       text;
  v_next_at_ts    timestamptz;

  v_result        public.inquiries;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  IF v_role IS NULL OR v_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION '권한이 없습니다. (운영진 전용)';
  END IF;

  SELECT *
  INTO v_row
  FROM public.inquiries
  WHERE id = p_inquiry_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '문의를 찾을 수 없습니다.';
  END IF;

  IF v_row.comments IS NULL
     OR jsonb_typeof(v_row.comments) <> 'array' THEN
    RAISE EXCEPTION '회신을 찾을 수 없습니다.';
  END IF;

  -- 삭제 대상 정보
  SELECT
    t.ord,
    (
      (t.elem ->> 'is_admin') = 'true'
      OR (t.elem ->> 'role') IN ('admin', 'staff')
    )
  INTO
    v_del_ord,
    v_del_is_op
  FROM jsonb_array_elements(v_row.comments)
       WITH ORDINALITY AS t(elem, ord)
  WHERE (t.elem ->> 'id') = p_comment_id::text
  ORDER BY t.ord
  LIMIT 1;

  IF v_del_ord IS NULL THEN
    RAISE EXCEPTION '회신을 찾을 수 없습니다.';
  END IF;

  -- 삭제 전 배열의 최초 운영진 댓글
  SELECT t.ord
  INTO v_first_op_ord
  FROM jsonb_array_elements(v_row.comments)
       WITH ORDINALITY AS t(elem, ord)
  WHERE
    (t.elem ->> 'is_admin') = 'true'
    OR (t.elem ->> 'role') IN ('admin', 'staff')
  ORDER BY t.ord
  LIMIT 1;

  v_is_answer_src := (
    COALESCE(v_del_is_op, false)
    AND v_first_op_ord IS NOT NULL
    AND v_del_ord = v_first_op_ord
  );

  -- 대상 댓글 1개 제거
  SELECT COALESCE(
    jsonb_agg(elem ORDER BY ord),
    '[]'::jsonb
  )
  INTO v_new_comments
  FROM jsonb_array_elements(v_row.comments)
       WITH ORDINALITY AS t(elem, ord)
  WHERE (elem ->> 'id') IS DISTINCT FROM p_comment_id::text;

  v_new_len := jsonb_array_length(v_new_comments);

  -- 최초 운영진 댓글을 삭제한 경우 다음 운영진 댓글 탐색
  IF v_is_answer_src THEN
    SELECT
      t.elem ->> 'content',
      t.elem ->> 'author',
      t.elem ->> 'created_at'
    INTO
      v_next_content,
      v_next_author,
      v_next_at
    FROM jsonb_array_elements(v_new_comments)
         WITH ORDINALITY AS t(elem, ord)
    WHERE
      (t.elem ->> 'is_admin') = 'true'
      OR (t.elem ->> 'role') IN ('admin', 'staff')
    ORDER BY t.ord
    LIMIT 1;

    IF v_next_content IS NOT NULL THEN
      -- created_at 레거시 호환 방어
      IF v_next_at IS NOT NULL
         AND v_next_at ~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}' THEN
        BEGIN
          v_next_at_ts := v_next_at::timestamptz;
        EXCEPTION
          WHEN others THEN
            v_next_at_ts := now();
        END;
      ELSE
        v_next_at_ts := now();
      END IF;
    ELSE
      v_next_at_ts := NULL;
    END IF;
  END IF;

  UPDATE public.inquiries
  SET
    comments = v_new_comments,

    answer = CASE
      WHEN v_new_len = 0 THEN NULL
      WHEN v_is_answer_src THEN v_next_content
      ELSE answer
    END,

    answered_by = CASE
      WHEN v_new_len = 0 THEN NULL
      WHEN v_is_answer_src THEN v_next_author
      ELSE answered_by
    END,

    answered_at = CASE
      WHEN v_new_len = 0 THEN NULL
      WHEN v_is_answer_src THEN v_next_at_ts
      ELSE answered_at
    END

  WHERE id = p_inquiry_id
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL
ON FUNCTION public.delete_inquiry_comment(uuid, uuid)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.delete_inquiry_comment(uuid, uuid)
TO authenticated;


-- ------------------------------------------------------------
-- 5. 문의 삭제 RLS
--
-- 일반 유저:
--   - 자기 문의
--   - answer 없음
--   - comments 없음/빈 배열
--   - status가 NULL 또는 접수됨
--
-- 운영진:
--   - admin / staff 무조건 삭제 가능
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "문의 삭제" ON public.inquiries;

CREATE POLICY "문의 삭제"
ON public.inquiries
FOR DELETE
USING (
  (
    auth.uid() = user_id
    AND answer IS NULL
    AND (
      comments IS NULL
      OR CASE
        WHEN jsonb_typeof(comments::jsonb) = 'array'
          THEN jsonb_array_length(comments::jsonb) = 0
        ELSE false
      END
    )
    AND (status IS NULL OR status = '접수됨')
  )
  OR (
    (auth.jwt() -> 'app_metadata' ->> 'role')
      IN ('admin', 'staff')
  )
);


-- ------------------------------------------------------------
-- 6. 적용 후 확인용 쿼리
-- ------------------------------------------------------------

-- 모든 array 댓글에 UUID id가 존재하는지 확인
-- SELECT
--   i.id AS inquiry_id,
--   elem ->> 'id' AS comment_id
-- FROM public.inquiries i
-- CROSS JOIN LATERAL jsonb_array_elements(
--   CASE
--     WHEN jsonb_typeof(i.comments) = 'array' THEN i.comments
--     ELSE '[]'::jsonb
--   END
-- ) AS t(elem)
-- WHERE NOT (
--   (elem ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
-- );

-- 정책 확인
-- SELECT policyname, cmd, qual
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename = 'inquiries'
-- ORDER BY policyname;

-- 함수 속성/권한 확인
-- SELECT
--   p.proname,
--   p.prosecdef,
--   has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_exec,
--   has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_exec
-- FROM pg_proc p
-- WHERE p.proname IN (
--   'add_inquiry_comment',
--   'update_inquiry_comment',
--   'delete_inquiry_comment'
-- )
-- ORDER BY p.proname;

-- ============================================================
-- 필수 실제 계정 테스트
--
-- 1. admin → 타인 댓글 수정 성공
-- 2. admin → 타인 댓글 삭제 성공
-- 3. staff → 타인 댓글 수정 성공
-- 4. staff → 타인 댓글 삭제 성공
-- 5. 일반 유저 → 수정/삭제 RPC 직접 호출 실패
-- 6. 일반 유저 → 기존 append-only 댓글 추가 정상
-- 7. admin/staff → 문의 전체 삭제 가능
-- 8. 일반 유저 → 기존 문의 삭제 제한 그대로 유지
-- 9. 최초 운영진 댓글 수정 시 answer 동기화
-- 10. 후속 운영진 댓글 수정 시 answer 불변
-- 11. 최초 운영진 댓글 삭제 시 다음 운영진 댓글로 answer 재동기화
-- 12. 운영진 댓글이 더 없으면 answer 3필드 NULL
-- ============================================================
