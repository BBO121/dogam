-- ============================================
-- 진단 전용 (읽기 전용, DDL/DML 없음) — my-characters.html 403 원인 확인
-- 작성일: 2026-08-15
--
-- privacy_fix_patch2.sql 실행 후 로그인 계정에서 characters SELECT가
-- authenticated 권한으로 403(permission denied)이 나는 원인을 확인합니다.
-- 컬럼 목록 자체(GRANT 목록 vs getMyCharacters() SELECT 목록)는 이미
-- 1:1 대조 완료했고 완전히 일치합니다 — 그런데도 403이 난다는 건
-- authenticated role에 대한 GRANT 자체가 DB에 실제로 반영 안 됐을
-- 가능성이 가장 유력합니다. 아래로 직접 확인합니다.
-- ============================================

-- ────────────────────────────────────────────
-- A. characters에 대해 anon/authenticated가 실제로 가진 "컬럼별" SELECT 권한
--    (컬럼 단위 GRANT는 information_schema.column_privileges에서 role별로 조회 가능)
-- ────────────────────────────────────────────
SELECT
  grantee,
  column_name,
  privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'characters'
  AND grantee IN ('anon', 'authenticated')
  AND privilege_type = 'SELECT'
ORDER BY grantee, column_name;

-- 기대 결과: grantee='authenticated'인 행이 36개(owner_contact/designer_contact/
-- designer_external 제외 전체 안전 컬럼) 나와야 합니다. anon도 동일하게 36개여야
-- 합니다. 만약 authenticated 행이 0개거나 36개보다 적다면 그게 바로 원인입니다.


-- ────────────────────────────────────────────
-- B. characters에 대한 "테이블 레벨" 권한도 남아있는지 확인
--    (테이블 레벨 SELECT가 여전히 있다면 컬럼 권한과 무관하게 전체 접근이
--    되어야 정상인데 403이 난다는 건 테이블 레벨도 막혀있다는 뜻 — 참고용)
-- ────────────────────────────────────────────
SELECT
  grantee,
  privilege_type,
  is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'characters'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee, privilege_type;

-- 기대 결과: SELECT 권한을 가진 행이 anon/authenticated 어느 쪽에도 없어야
-- 정상입니다(테이블 레벨 SELECT는 우리가 의도적으로 REVOKE했으므로 — 대신
-- 위 A의 컬럼 단위 권한으로만 접근 가능해야 합니다). INSERT/UPDATE/DELETE
-- 권한은 이 패치와 무관하니 남아있어도 정상입니다.


-- ────────────────────────────────────────────
-- C. characters에 RLS(행 단위 보안)가 켜져 있는지, 정책이 있는지
--    (403은 보통 컬럼/테이블 권한 문제지만, 혹시 이번에 처음 RLS까지
--    걸려있는 상태였는지 배제하기 위해 확인)
-- ────────────────────────────────────────────
SELECT relrowsecurity, relforcerowsecurity
FROM pg_catalog.pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relname = 'characters';

SELECT policyname, roles, cmd, qual
FROM pg_catalog.pg_policies
WHERE schemaname = 'public'
  AND tablename = 'characters';

-- 기대 결과: relrowsecurity = false(또는 true인데 정책이 있어서 anon도
-- 이미 정상 조회되고 있었던 것과 모순 없이 설명 가능해야 함). 정책 목록이
-- 비어있다면 RLS는 이번 문제와 무관하다는 뜻입니다.


-- ────────────────────────────────────────────
-- D. delete_user / get_character_for_edit / resolve_users_by_* 도
--    같은 종류의 GRANT 누락이 없는지 겸사겸사 확인(선택)
-- ────────────────────────────────────────────
SELECT
  p.proname AS function_name,
  r.rolname AS grantee,
  has_function_privilege(r.oid, p.oid, 'EXECUTE') AS can_execute
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN pg_catalog.pg_roles r
WHERE n.nspname = 'public'
  AND p.proname IN ('delete_user', 'get_character_for_edit',
                     'resolve_users_by_identifiers', 'resolve_users_by_ids')
  AND r.rolname IN ('anon', 'authenticated')
ORDER BY function_name, grantee;

-- 기대 결과: authenticated는 4개 함수 전부 can_execute = true,
-- anon은 4개 전부 can_execute = false여야 합니다.
