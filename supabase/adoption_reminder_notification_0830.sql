-- ============================================================
-- [기능] 분양글 진행시간 도래 시 종족주 리마인드 알림 자동 발송
-- 작성일: 2026-08-30
--
-- 대상:
--   adoption_type = 'free'
--   AND free_type = 'random'
--
-- 동작:
--   무료 랜덤 추첨 분양글의 raffle_at이 도래하면
--   해당 종족의 종족주에게 사이트 알림을 자동 발송한다.
--
-- 실행 방식:
--   pg_cron이 5분마다 public.send_adoption_reminders() 실행
--
-- 알림:
--   type    : adoption_reminder
--   message : ⏰ "개체명" 무료 분양 추첨 시간이 되었어요.
--             추첨을 진행해주세요!
--   link    : adoption-detail.html?id={adoption_id}
--
-- 중요:
--   - 클라이언트 JS에 의존하지 않음
--   - notify_user_by_id() 성공 후에만 reminder_sent_at 기록
--   - 종족주 조회 실패 시 reminder_sent_at을 기록하지 않고 재시도
--   - FOR UPDATE SKIP LOCKED로 cron 동시 실행 중복 방지
--   - 설치 이전 과거 분양글에는 소급 알림하지 않음
--
-- 향후:
--   경매 종료 리마인드 등 다른 종류의 리마인드를 추가할 경우
--   reminder_sent_at 하나를 공용으로 사용하면 안 됨.
--   유형별 sent_at 컬럼 또는 별도 reminder log 구조로 확장할 것.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. 중복 발송 방지 컬럼
-- ============================================================

ALTER TABLE public.adoptions
ADD COLUMN IF NOT EXISTS reminder_sent_at timestamptz;


COMMENT ON COLUMN public.adoptions.reminder_sent_at IS
'종족주 리마인드 알림(adoption_reminder) 발송 시각. NULL이면 미발송. send_adoption_reminders()가 중복 발송 방지에 사용.';


-- ============================================================
-- 2. 기존 과거 분양글 초기화
-- ============================================================
--
-- 이 기능을 처음 설치할 때 기존 모든 adoptions의
-- reminder_sent_at은 NULL 상태다.
--
-- 따라서 예전에 추첨 시각이 이미 지났지만
-- status가 아직 '분양중'으로 남아 있는 글까지
-- 설치 직후 리마인드가 발송될 수 있다.
--
-- 기존 과거 건은 "이미 처리된 리마인드"로 초기화하고,
-- 현재 시점 이후 raffle_at이 도래하는 글부터 알림을 발송한다.
--
-- ※ 이미 reminder_sent_at이 존재하는 경우는 건드리지 않는다.

UPDATE public.adoptions
SET reminder_sent_at = now()
WHERE adoption_type = 'free'
  AND free_type = 'random'
  AND status = '분양중'
  AND raffle_at IS NOT NULL
  AND raffle_at <= now()
  AND reminder_sent_at IS NULL;


-- ============================================================
-- 3. 리마인드 발송 함수
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_adoption_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row       record;
    v_owner_id  uuid;
    v_link      text;
    v_sent      integer := 0;

BEGIN

    -- --------------------------------------------------------
    -- 대상 조건
    --
    -- 무료 랜덤 추첨
    -- 현재도 분양중
    -- 추첨시간 존재
    -- 추첨시간 도래
    -- 아직 리마인드 미발송
    --
    -- FOR UPDATE SKIP LOCKED:
    -- cron이 동시에 두 번 실행돼도 같은 adoption 행을
    -- 두 트랜잭션이 동시에 처리하지 못하도록 행 잠금.
    -- --------------------------------------------------------

    FOR v_row IN

        SELECT *
        FROM public.adoptions
        WHERE adoption_type = 'free'
          AND free_type = 'random'
          AND status = '분양중'
          AND raffle_at IS NOT NULL
          AND raffle_at <= now()
          AND reminder_sent_at IS NULL
        FOR UPDATE SKIP LOCKED

    LOOP

        v_owner_id := NULL;


        -- ====================================================
        -- 3-1. 종족주 조회
        -- ====================================================

        IF v_row.character_id IS NOT NULL THEN

            -- 캐릭터 분양
            --
            -- 기존 adoption_rule_*.sql의 종족주 판별 방식과 동일:
            -- characters.species_name = species.name

            SELECT sp.owner_user_id
            INTO v_owner_id
            FROM public.characters c
            LEFT JOIN public.species sp
              ON sp.name = c.species_name
            WHERE c.id = v_row.character_id;


        ELSIF v_row.slot_id IS NOT NULL THEN

            -- 디자인권(슬롯) 분양

            SELECT sp.owner_user_id
            INTO v_owner_id
            FROM public.slots sl
            JOIN public.species sp
              ON sp.id = sl.species_id
            WHERE sl.id = v_row.slot_id;

        END IF;


        -- ====================================================
        -- 3-2. 종족주 확인 실패
        -- ====================================================
        --
        -- owner_user_id가 없거나 species 조인에 실패한 경우
        -- reminder_sent_at을 기록하지 않는다.
        --
        -- 따라서 다음 cron 실행에서 다시 시도된다.

        IF v_owner_id IS NULL THEN
            CONTINUE;
        END IF;


        -- ====================================================
        -- 3-3. 알림 발송
        -- ====================================================

        v_link :=
            'adoption-detail.html?id=' || v_row.id;


        -- 한 분양글의 오류가 다른 정상 분양글의
        -- 리마인드 발송까지 전부 롤백시키지 않도록
        -- 개별 건 단위로 예외 처리한다.

        BEGIN

            -- notify_user_by_id():
            --
            -- p_user_id가 NULL이 아닌 경우
            -- notifications INSERT를 반드시 시도한다.
            --
            -- INSERT 실패 시 내부 EXCEPTION 처리가 없기 때문에
            -- 예외가 이 블록까지 전달된다.

            PERFORM public.notify_user_by_id(
                v_owner_id,
                'adoption_reminder',
                '⏰ "' ||
                    COALESCE(v_row.character_name, '분양글') ||
                    '" 무료 분양 추첨 시간이 되었어요. 추첨을 진행해주세요!',
                v_link
            );


            -- ------------------------------------------------
            -- 중요:
            --
            -- 실제 notification INSERT가 정상 종료된 뒤에만
            -- reminder_sent_at을 기록한다.
            --
            -- 알림 INSERT가 실패하면 아래 UPDATE까지 도달하지 않으며
            -- reminder_sent_at은 NULL 상태로 유지된다.
            -- ------------------------------------------------

            UPDATE public.adoptions
            SET reminder_sent_at = now()
            WHERE id = v_row.id;


            v_sent := v_sent + 1;


        EXCEPTION
            WHEN OTHERS THEN

                -- 해당 분양글은 reminder_sent_at이 NULL로 유지됨.
                -- 다음 cron에서 다시 재시도.
                --
                -- 다른 정상 분양글 처리는 계속 진행한다.

                RAISE WARNING
                    '[adoption reminder] adoption_id=% 발송 실패: %',
                    v_row.id,
                    SQLERRM;

        END;

    END LOOP;


    RETURN v_sent;

END;
$$;


COMMENT ON FUNCTION public.send_adoption_reminders() IS
'무료 랜덤 추첨 분양 중 raffle_at이 도래했지만 아직 추첨 전인 건을 찾아 종족주에게 adoption_reminder 알림을 1회 발송한다. notification INSERT 성공 후에만 reminder_sent_at을 기록한다. 종족주 조회 또는 알림 발송 실패 건은 reminder_sent_at을 NULL로 유지해 다음 cron에서 재시도한다.';


-- ============================================================
-- 4. 함수 실행 권한 제한
-- ============================================================
--
-- 일반 사용자가 Supabase RPC로 직접 호출할 필요가 없는
-- 내부 cron 전용 함수.

REVOKE ALL
ON FUNCTION public.send_adoption_reminders()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.send_adoption_reminders()
FROM anon;

REVOKE ALL
ON FUNCTION public.send_adoption_reminders()
FROM authenticated;


-- ============================================================
-- 5. pg_cron 활성화
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;


-- ============================================================
-- 6. cron 등록
-- ============================================================
--
-- 이름 있는 cron.schedule은 동일 username + jobname 기준으로
-- 기존 job을 갱신하므로 같은 SQL을 다시 실행해도
-- 동일 이름 job이 계속 중복 생성되지 않는다.
--
-- 5분마다 실행.

SELECT cron.schedule(
    'adoption-reminder-free-random',
    '*/5 * * * *',
    $$ SELECT public.send_adoption_reminders(); $$
);


COMMIT;



-- ============================================================
-- 실행 후 확인
-- ============================================================


-- ------------------------------------------------------------
-- 1. cron 등록 확인
-- ------------------------------------------------------------

-- SELECT
--     jobid,
--     jobname,
--     schedule,
--     command,
--     active
-- FROM cron.job
-- WHERE jobname = 'adoption-reminder-free-random';


-- ------------------------------------------------------------
-- 2. 수동 1회 실행
-- ------------------------------------------------------------
--
-- Supabase SQL Editor의 postgres 권한에서 실행.
--
-- 반환값:
-- 이번 실행에서 정상 발송된 알림 수.

-- SELECT public.send_adoption_reminders();


-- ------------------------------------------------------------
-- 3. 현재 리마인드 대상 확인
-- ------------------------------------------------------------

-- SELECT
--     id,
--     character_name,
--     adoption_type,
--     free_type,
--     status,
--     raffle_at,
--     reminder_sent_at
-- FROM public.adoptions
-- WHERE adoption_type = 'free'
--   AND free_type = 'random'
--   AND status = '분양중'
--   AND raffle_at IS NOT NULL
-- ORDER BY raffle_at DESC;


-- ------------------------------------------------------------
-- 4. 생성된 리마인드 알림 확인
-- ------------------------------------------------------------

-- SELECT
--     id,
--     user_id,
--     user_nickname,
--     type,
--     message,
--     link,
--     is_read,
--     created_at
-- FROM public.notifications
-- WHERE type = 'adoption_reminder'
-- ORDER BY created_at DESC;


-- ============================================================
-- 테스트 방법
-- ============================================================
--
-- 1)
-- 테스트용 무료 랜덤 추첨 분양글을 준비한다.
--
-- adoption_type = 'free'
-- free_type     = 'random'
-- status        = '분양중'
--
--
-- 2)
-- raffle_at을 현재보다 약 5~10분 뒤로 설정한다.
--
--
-- 3)
-- 시간 전 확인:
--
-- SELECT public.send_adoption_reminders();
--
-- → 0 반환
-- → notifications 없음
-- → reminder_sent_at NULL
--
--
-- 4)
-- raffle_at 도래 후 cron 또는 수동 함수 실행
--
-- → 1 반환
--
--
-- 5)
-- 해당 adoption 확인
--
-- reminder_sent_at IS NOT NULL
--
--
-- 6)
-- notifications 확인
--
-- type = 'adoption_reminder'
--
-- message 예:
--
-- ⏰ "체리" 무료 분양 추첨 시간이 되었어요.
-- 추첨을 진행해주세요!
--
--
-- 7)
-- 종족주 계정으로 알림함 확인
--
-- 알림 클릭 시:
--
-- adoption-detail.html?id={adoption_id}
--
-- 로 정상 이동하는지 확인.
--
--
-- 8)
-- 함수 재실행
--
-- SELECT public.send_adoption_reminders();
--
-- → 0 반환
-- → 같은 adoption_reminder 추가 생성 안 됨
--
--
-- 9)
-- status를 미리
--
-- '확인 대기중'
-- 또는
-- '완료'
--
-- 로 변경한 분양은 알림 생성 안 되는지 확인.
--
--
-- 10)
-- raffle_at이 NULL인 분양도 알림 생성 안 되는지 확인.
--
--
-- 11)
-- 일반 유저에게는 알림이 가지 않고
-- species.owner_user_id 종족주에게만 가는지 확인.
--
--
-- 12)
-- 화면에 표시되는 KST 추첨시간과
-- DB raffle_at 실제 timestamptz 값이 일치하는지 확인.
--
-- timestamptz끼리 now()와 직접 비교하므로
-- DB 내부 비교 자체에는 UTC/KST 변환이 필요하지 않음.
--
-- 단, 분양 등록 프론트엔드가 KST 입력값을
-- 올바른 timestamptz로 저장하고 있는지는 별도 확인.


-- ============================================================
-- 특정 테스트 분양글 결과 한번에 확인
-- ============================================================
--
-- 아래 TEST_ADOPTION_ID를 실제 ID로 교체.

-- SELECT
--     a.id,
--     a.character_name,
--     a.raffle_at,
--     a.status,
--     a.reminder_sent_at,
--
--     n.id AS notification_id,
--     n.user_id,
--     n.type,
--     n.message,
--     n.created_at
--
-- FROM public.adoptions a
--
-- LEFT JOIN public.notifications n
--   ON n.type = 'adoption_reminder'
--  AND n.link = 'adoption-detail.html?id=' || a.id
--
-- WHERE a.id = TEST_ADOPTION_ID
--
-- ORDER BY n.created_at DESC;


-- ============================================================
-- Rollback
-- ============================================================
--
-- 주의:
-- 아래는 이 기능 자체를 완전히 제거할 때만 실행.


-- SELECT cron.unschedule(
--     'adoption-reminder-free-random'
-- );


-- DROP FUNCTION IF EXISTS
--     public.send_adoption_reminders();


-- ALTER TABLE public.adoptions
--     DROP COLUMN IF EXISTS reminder_sent_at;