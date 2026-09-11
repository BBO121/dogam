-- ============================================================
-- owner_custom_name 컬럼 단위 GRANT 누락 수정
-- 작성일: 2026-09-12
--
-- [문제]
-- character_owner_custom_name_0912.sql(이미 실행됨)에서 characters.owner_custom_name
-- 컬럼을 추가했지만, 이 테이블은 privacy_fix_patch2.sql에서 테이블 레벨 SELECT를
-- REVOKE하고 "안전 컬럼만" 컬럼 단위로 GRANT하는 방식으로 바뀌어 있다(그 이후
-- character_artist_setup.sql이 artist_* 3컬럼 추가 시 동일하게 GRANT를 함께
-- 챙긴 선례가 있음). owner_custom_name 추가 시 이 GRANT를 빠뜨렸다.
--
-- 결과: characters_public 뷰(뷰 소유자 권한으로 원본을 읽어 REVOKE와 무관하게
-- 항상 동작 — character.html 등)는 영향 없지만, 원본 테이블에 직접 쿼리하는
-- js/auth.js getMyCharacters()(pages/my-characters.html이 사용)가
-- select 목록에 owner_custom_name을 추가한 뒤로 authenticated 컬럼 권한이
-- 없어 권한 오류(42501)로 실패할 수 있다. anon 키로 직접 재현 확인함
-- (컬럼 없음이 아니라 "permission denied for table characters" 로 테이블
-- 레벨부터 막히는 걸 확인 — 컬럼 단위 GRANT가 authenticated에도 없다는 뜻).
--
-- [해결]
-- character_artist_setup.sql의 GRANT 패턴 그대로, owner_custom_name 한
-- 컬럼만 추가로 컬럼 단위 GRANT한다. owner_custom_name은 characters_public
-- 뷰를 통해 이미 누구나(anon 포함) 열람 가능한 값이라 anon까지 포함해도
-- 새로운 노출은 아니다 — 다른 안전 컬럼들과 동일한 공개 수준으로 맞추는 것뿐.
-- ============================================================

GRANT SELECT (owner_custom_name)
  ON public.characters
  TO anon, authenticated;
