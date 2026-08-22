BEGIN;

DROP POLICY IF EXISTS "로그인 유저 분양 등록"
ON public.adoptions;

CREATE POLICY "로그인 유저 분양 등록"
ON public.adoptions
FOR INSERT
TO authenticated
WITH CHECK (

  -- ------------------------------------------------------------
  -- 작성자 신원 검증
  -- ------------------------------------------------------------
  user_id = auth.uid()

  AND author = COALESCE(
    NULLIF(
      (auth.jwt() -> 'user_metadata'::text) ->> 'display_name'::text,
      ''::text
    ),
    (auth.jwt() -> 'user_metadata'::text) ->> 'nickname'::text
  )

  -- ------------------------------------------------------------
  -- adoption_type 공통 유효성 검증
  -- ------------------------------------------------------------
  AND adoption_type IN (
    'free',
    'paid',
    'auction',
    'etc'
  )

  AND (

    -- ==========================================================
    -- 1. 캐릭터 분양
    -- ==========================================================
    (
      character_id IS NOT NULL
      AND slot_id IS NULL

      AND EXISTS (
        SELECT 1
        FROM public.characters c
        LEFT JOIN public.species sp
          ON sp.name = c.species_name

        WHERE c.id = adoptions.character_id

          -- 반드시 본인 소유 개체
          AND c.owner_user_id = auth.uid()

          AND (

            -- 해당 종족 종족주는 분양 규칙만 예외
            (
              sp.owner_user_id IS NOT NULL
              AND sp.owner_user_id = auth.uid()
            )

            OR

            -- 일반 유저 분양 규칙 적용
            (
              COALESCE(
                c.allow_resale,
                sp.allow_resale,
                true
              )

              AND CASE adoptions.adoption_type

                WHEN 'free' THEN
                  COALESCE(
                    c.allow_free_adoption,
                    sp.allow_free_adoption,
                    true
                  )

                WHEN 'paid' THEN
                  COALESCE(
                    c.allow_paid_adoption,
                    sp.allow_paid_adoption,
                    true
                  )

                WHEN 'auction' THEN
                  COALESCE(
                    c.allow_paid_adoption,
                    sp.allow_paid_adoption,
                    true
                  )

                WHEN 'etc' THEN
                  COALESCE(
                    c.allow_other_adoption,
                    sp.allow_other_adoption,
                    true
                  )

                ELSE false
              END
            )
          )
      )
    )

    OR

    -- ==========================================================
    -- 2. 디자인권(슬롯) 분양
    -- ==========================================================
    (
      character_id IS NULL
      AND slot_id IS NOT NULL

      AND EXISTS (
        SELECT 1
        FROM public.slots sl
        JOIN public.species sp
          ON sp.id = sl.species_id

        WHERE sl.id = adoptions.slot_id
          AND sp.owner_user_id = auth.uid()
      )
    )

  )
);

COMMIT;