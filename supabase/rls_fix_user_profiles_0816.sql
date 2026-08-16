-- ============================================================
-- [CRITICAL 1] user_profiles RLS 최소권한 패치 (초안, 미실행)
-- 작성일: 2026-08-16
-- 목적: "Authenticated can write" (FOR ALL, USING(true)) 정책 제거.
--       로그인 사용자가 타인 프로필을 upsert 하지 못하도록 본인 행만 쓰기 허용.
--
-- 조사 결과 요약:
--   - 저장소 전체에서 user_profiles UPDATE/DELETE 호출 0건. 모든 쓰기는
--     upsert(..., {onConflict:'user_id'}) 이며 전부 user_id: currentUser.id (본인만).
--   - SELECT는 공개 프로필 열람 기능 때문에 타인 조회가 정상 동작이므로 건드리지 않음
--     (공개 SELECT 정책은 이 패치에서 변경하지 않음 - 뽀 지시사항 준수).
--   - 관리자가 타인 프로필을 수정하는 프론트/RPC 기능 없음 -> 관리자 예외 정책 불필요.
--   - DELETE를 쓰는 기능이 전혀 없으므로 DELETE 정책은 생성하지 않음(=차단 상태 유지).
--
-- 영향 프론트: pages/profile.html (아바타/워터마크/bio/tos/닉네임 upsert),
--             pages/achievements.html (featured_achievements upsert)
-- ============================================================

-- 기존 정책 제거 (뽀가 대시보드에서 확인한 정책명 그대로)
DROP POLICY IF EXISTS "Authenticated can write" ON public.user_profiles;

-- 본인 행 INSERT만 허용
CREATE POLICY "user_profiles_insert_own"
ON public.user_profiles
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- 본인 행 UPDATE만 허용
CREATE POLICY "user_profiles_update_own"
ON public.user_profiles
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- DELETE 정책은 의도적으로 생성하지 않음 (현재 기능에서 미사용 -> 기본 차단 유지)
-- 공개 SELECT 정책은 그대로 유지 (변경 없음)
