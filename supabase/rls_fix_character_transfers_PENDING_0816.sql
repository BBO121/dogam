-- ============================================================
-- ⚠️ 미적용 (PENDING) — 아직 Supabase에 실행하지 않음
-- 선행 조건: character_id 전달 프론트 수정(커밋 f89ba64) 배포 확인 +
-- 사이트에서 정상 이전 흐름(종족주 대리 이전/당첨자 확인/분양 완료처리) 검증 후 실행할 것
-- ============================================================
-- [보강] character_transfers INSERT 신원/이력 위조 방지 - 2차 배치
-- 작성일: 2026-08-16
--
-- 전제: js/auth.js logTransfer(), pages/character.html, pages/species.html,
-- pages/adoption-detail.html(2곳)이 character_id를 함께 보내도록 프론트
-- 수정 완료(이 패치와 같은 배포에 포함되어야 함 - 프론트 수정 없이 이 SQL만
-- 먼저 적용하면 4개 경로 전부 character_id가 NULL로 들어가 계속 통과는 되지만
-- 캐릭터 연동 검증 효과가 없어짐. 순서: 프론트 배포 -> 이 SQL 적용 권장,
-- 또는 동시 배포).
--
-- 핵심 불변식: character_transfers INSERT 시점엔 실제 소유권 이전이 이미
-- 끝난 뒤이므로(characters UPDATE 또는 RPC가 logTransfer보다 먼저 실행됨),
-- character_id가 있는 행은 "그 캐릭터의 현재 실제 owner_user_id가 이 로그의
-- to_user_id와 일치하는가"로 검증 가능. RLS로 보호되는 characters UPDATE를
-- 실제로 통과해야만 만족되므로 위조 불가.
--
-- character_id가 NULL인 행(디자인권/슬롯 분양 완료 - 실제 characters 행이
-- 없는 정상 케이스)은 기존처럼 from/to/종족주 조건으로만 검증.
--
-- 잔여 위험(허용 범위로 판단): character_id를 NULL로 보내면 여전히
-- from_user_id/character_name/species_name을 임의 문자열로 채운 "가짜 이력"을
-- 만들 수 있음(단, 실제 caracters 행과 연결되지 않으므로 특정 캐릭터의
-- 소유권/이력을 도용하는 건 불가능 - 텍스트성 로그 왜곡에 그침). 완전 차단하려면
-- 프론트가 언제나 slot_id 등 추가 근거를 함께 보내고 그것까지 검증하는
-- 후속 작업이 필요하나, 이번 범위(최소 침습)에서는 제외.
-- ============================================================

DROP POLICY IF EXISTS "이전내역 기록" ON public.character_transfers;
CREATE POLICY "이전내역 기록" ON public.character_transfers
FOR INSERT TO authenticated
WITH CHECK (
  (
    from_user_id = auth.uid()
    OR to_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.species
      WHERE species.name = character_transfers.species_name
        AND species.owner_user_id = auth.uid()
    )
  )
  AND (
    character_id IS NULL
    OR EXISTS (
      SELECT 1 FROM public.characters
      WHERE characters.id = character_transfers.character_id
        AND characters.owner_user_id = character_transfers.to_user_id
    )
  )
);
