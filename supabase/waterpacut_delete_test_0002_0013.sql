-- 워터파컷(species_id=186) 테스트 등록분 삭제: 0002~0013
-- 작성일: 2026-08-18
-- 엑셀 재정리로 인해 기존 테스트 등록분(002~013)을 지우고 새 데이터로 재등록하기 위한 스크립트.
-- character_gallery, species_steps 쪽 하위 레코드는 ON DELETE CASCADE로 함께 정리됨.
--
-- 주의: 001번(id=4836)은 char_number가 "001"(3자리)로 등록돼 있어 다른 행들과 자릿수가 다르다.
-- BETWEEN 같은 문자열 범위 비교를 쓰면 "001"이 사전식으로 '0002'~'0013' 사이에 껴서 잘못 걸릴 수 있으므로
-- 반드시 아래처럼 명시적 IN 목록으로 비교한다.

-- 1) 먼저 삭제 대상 확인 (실행해서 12건 맞는지 눈으로 확인 — 001(id=4836)이 없어야 정상)
SELECT id, char_number, name, owner_nickname, designer_nickname, created_at
FROM public.characters
WHERE species_name = '워터파컷'
  AND char_number IN ('0002','0003','0004','0005','0006','0007','0008','0009','0010','0011','0012','0013')
ORDER BY char_number;

-- 2) 확인 후 아래 DELETE 실행
DELETE FROM public.characters
WHERE species_name = '워터파컷'
  AND char_number IN ('0002','0003','0004','0005','0006','0007','0008','0009','0010','0011','0012','0013');

-- 001번(id=4836)은 char_number "001"(3자리) 그대로 유지 — 앞으로 워터파컷은 3자리 형식으로 통일하기로 함.
-- 재등록용 JSON도 001~211 3자리 형식으로 다시 생성해둠. UPDATE 불필요.
