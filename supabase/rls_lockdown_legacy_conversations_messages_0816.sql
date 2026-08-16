-- ============================================================
-- [CRITICAL 3] legacy conversations / messages 잠금 패치 (초안, 미실행)
-- 작성일: 2026-08-16
-- 목적: 로그인 사용자 전체가 모든 행에 접근 가능한 상태(USING(true)) 제거.
--       테이블/데이터는 삭제하지 않고 API 접근만 차단(=서비스 계층에서만 접근 가능).
--
-- 조사 결과 요약:
--   - 신규 DM은 dm_rooms/dm_messages/dm_message_attachments 등 dm_ 접두사 테이블만 사용
--     (js/chat.js 전체가 dm_ 테이블만 참조, conversations/messages 문자열 0건).
--   - conversations/messages 테이블을 참조하는 코드는 pages/chat.html, pages/messages.html
--     뿐이며, 두 페이지 모두 사이트 내 어디서도 링크되지 않는 고아 페이지
--     (sidebar.js, main.js 등 전체 검색 결과 이 두 페이지로의 링크 0건).
--   - 즉 URL을 직접 입력해야만 도달 가능한, 사실상 미사용 상태.
--   - 데이터 이관/폐기 커밋 없음 -> 기존 데이터가 남아있을 수 있으므로 DROP TABLE 금지,
--     RLS만 잠가 데이터는 보존.
--
-- 참고: 이 패치를 적용하면 pages/chat.html, pages/messages.html을 직접 URL로 열었을 때
--       데이터 조회/전송이 전부 실패(빈 화면 또는 에러)합니다. 두 페이지 파일 자체를
--       삭제/리다이렉트할지는 별도로 뽀의 명시적 지시가 있을 때 진행합니다
--       (CLAUDE.md: 기존 기능 삭제는 명시적 요청 시에만).
-- ============================================================

-- 기존 정책 전체 동적 제거
DO $$
DECLARE pol record; t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['conversations', 'messages'] LOOP
    FOR pol IN
      SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename = t
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
  END LOOP;
END $$;

-- RLS는 계속 켜둔 채(정책 0개) 유지 -> anon/authenticated 전원 접근 불가.
-- service_role(관리 스크립트/백엔드)은 RLS를 우회하므로 필요 시 데이터 이관/조회 가능.
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
