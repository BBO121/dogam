-- ============================================
-- 개체 추가 등록 신청 (1차 — 융용 아기융)
-- 작성일: 2026-08-10
--
-- 실제 characters에 즉시 등록하지 않고
-- 유저의 추가 등록 신청만 저장한다.
--
-- request_type:
--   existing_character_baby_step
--     → 이미 등록된 성장 개체에 아기융 Step 추가
--
--   baby_only
--     → 성장 버전 없이 아기융 단독 신규 등록
--
--   new_growth_character
--     → 아기융 + 성장 단계가 존재하는 신규 개체 등록
--
-- growth_steps:
--   아기융(Step 1)은 별도 컬럼에 저장하고
--   이후 단계만 JSON 배열로 저장한다.
--
-- 예:
-- [
--   {
--     "step_name": "발탁용",
--     "image_url": "...",
--     "designer_nickname": "..."
--   }
-- ]
-- ============================================


-- ============================================
-- 1. 신청 테이블
-- ============================================

CREATE TABLE IF NOT EXISTS public.character_registration_requests (

  id uuid
    PRIMARY KEY
    DEFAULT gen_random_uuid(),

  request_type text
    NOT NULL
    CHECK (
      request_type IN (
        'existing_character_baby_step',
        'baby_only',
        'new_growth_character'
      )
    ),

  species_name text
    NOT NULL
    DEFAULT '융용',

  -- 신청자
  applicant_user_id uuid
    NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  -- 신청 당시 닉네임 스냅샷.
  -- 실제 등록 처리 시에는 applicant_user_id 기준으로
  -- 현재 닉네임을 다시 확인할 것.
  applicant_nickname text
    NOT NULL,

  -- 신청 상태
  status text
    NOT NULL
    DEFAULT 'pending'
    CHECK (
      status IN (
        'pending',
        'approved',
        'rejected'
      )
    ),

  -- ==========================================
  -- 기존 성장 개체에 아기융 추가 시 사용
  -- ==========================================

  existing_character_name text,

  -- ==========================================
  -- 아기융 정보
  -- 모든 신청 유형 공통 필수
  -- ==========================================

  baby_image_url text
    NOT NULL,

  baby_designer_nickname text
    NOT NULL,

  -- ==========================================
  -- 신규 성장 개체 정보
  -- ==========================================

  growth_steps jsonb
    NOT NULL
    DEFAULT '[]'::jsonb,

  post_growth_trait text,

  created_at timestamptz
    NOT NULL
    DEFAULT now(),

  updated_at timestamptz
    NOT NULL
    DEFAULT now()
);


COMMENT ON TABLE public.character_registration_requests IS
'유저가 제출한 개체 추가 등록 신청. characters 테이블에는 직접 반영되지 않으며 관리자가 신청 내용을 확인한 뒤 등록한다.';



-- ============================================
-- 2. growth_steps는 반드시 JSON 배열
-- ============================================

ALTER TABLE public.character_registration_requests
DROP CONSTRAINT IF EXISTS
character_registration_requests_growth_steps_is_array;


ALTER TABLE public.character_registration_requests
ADD CONSTRAINT
character_registration_requests_growth_steps_is_array

CHECK (
  jsonb_typeof(growth_steps) = 'array'
);



-- ============================================
-- 3. 신청 유형별 데이터 검증
-- ============================================

ALTER TABLE public.character_registration_requests
DROP CONSTRAINT IF EXISTS
character_registration_requests_type_data_check;


ALTER TABLE public.character_registration_requests
ADD CONSTRAINT
character_registration_requests_type_data_check

CHECK (

  -- ------------------------------------------
  -- 기존 성장 개체에 아기융 Step 추가
  -- → 기존 개체명이 반드시 있어야 함
  -- ------------------------------------------

  (
    request_type = 'existing_character_baby_step'

    AND existing_character_name IS NOT NULL
    AND btrim(existing_character_name) <> ''

    AND growth_steps = '[]'::jsonb
    AND post_growth_trait IS NULL
  )

  OR

  -- ------------------------------------------
  -- 아기융 단독 신규 등록
  -- → 성장 관련 데이터가 없어야 함
  -- ------------------------------------------

  (
    request_type = 'baby_only'

    AND existing_character_name IS NULL

    AND growth_steps = '[]'::jsonb
    AND post_growth_trait IS NULL
  )

  OR

  -- ------------------------------------------
  -- 아기융 + 성장 단계 신규 등록
  -- → 기존 개체명은 없어야 함
  -- → 후용성 필수
  -- ------------------------------------------

  (
    request_type = 'new_growth_character'

    AND existing_character_name IS NULL

    AND post_growth_trait IS NOT NULL
    AND btrim(post_growth_trait) <> ''
  )

);



-- ============================================
-- 4. updated_at 자동 갱신
-- ============================================

CREATE OR REPLACE FUNCTION
public.set_character_registration_requests_updated_at()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

  NEW.updated_at = now();

  RETURN NEW;

END;

$$;


DROP TRIGGER IF EXISTS
trg_character_registration_requests_updated_at
ON public.character_registration_requests;


CREATE TRIGGER
trg_character_registration_requests_updated_at

BEFORE UPDATE
ON public.character_registration_requests

FOR EACH ROW

EXECUTE FUNCTION
public.set_character_registration_requests_updated_at();



-- ============================================
-- 5. RLS 활성화
-- ============================================

ALTER TABLE public.character_registration_requests
ENABLE ROW LEVEL SECURITY;



-- 기존 정책 제거

DROP POLICY IF EXISTS
"character_registration_requests_select"
ON public.character_registration_requests;


DROP POLICY IF EXISTS
"character_registration_requests_insert"
ON public.character_registration_requests;



-- ============================================
-- 6. SELECT
--
-- 일반 유저:
--   본인 신청만 조회 가능
--
-- admin / staff:
--   전체 신청 조회 가능
--
-- 권한은 user_metadata가 아닌
-- app_metadata.role 기준
-- ============================================

CREATE POLICY
"character_registration_requests_select"

ON public.character_registration_requests

FOR SELECT

USING (

  applicant_user_id = auth.uid()

  OR

  (
    auth.jwt() -> 'app_metadata' ->> 'role'
  ) IN ('admin', 'staff')

);



-- ============================================
-- 7. INSERT
--
-- 로그인 유저는 본인 명의 신청만 가능.
--
-- 중요:
-- 클라이언트에서 status='approved' 등을
-- 임의로 넣지 못하도록 pending만 허용.
-- ============================================

CREATE POLICY
"character_registration_requests_insert"

ON public.character_registration_requests

FOR INSERT

WITH CHECK (

  applicant_user_id = auth.uid()

  AND status = 'pending'

);



-- ============================================
-- 8. UPDATE / DELETE
-- ============================================
--
-- 현재는 정책을 만들지 않는다.
--
-- 따라서 일반 유저는:
--   신청 수정 불가
--   신청 삭제 불가
--
-- 관리자 승인/거절 기능은
-- 추후 관리자 페이지 구현 시 별도 정책/RPC로 추가한다.
-- ============================================



-- ============================================
-- 9. 적용 확인
-- ============================================

SELECT
  column_name,
  data_type,
  is_nullable,
  column_default

FROM information_schema.columns

WHERE table_schema = 'public'
  AND table_name = 'character_registration_requests'

ORDER BY ordinal_position;



-- ============================================
-- 10. CHECK 제약 확인
-- ============================================

SELECT
  conname,
  pg_get_constraintdef(oid)

FROM pg_constraint

WHERE conrelid =
  'public.character_registration_requests'::regclass

ORDER BY conname;



-- ============================================
-- 11. RLS 정책 확인
-- ============================================

SELECT
  policyname,
  cmd,
  qual,
  with_check

FROM pg_policies

WHERE schemaname = 'public'
  AND tablename = 'character_registration_requests'

ORDER BY policyname;