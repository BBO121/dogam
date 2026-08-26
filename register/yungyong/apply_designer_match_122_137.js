// 아기융용-122 ~ 137 (2026-08-22 신규 등록분) 디자이너 매칭 반영 스크립트
// 검수 완료(뽀 확인) 후 확정된 목록만 반영합니다.
// yungyong-bulk-import.html 등 관리자 로그인된 페이지의 브라우저 콘솔에 붙여넣어 실행하세요.
//
// 매칭 확정 13건: designer_user_ids 채우고 designer_external은 비워서(사이트오프 배지 제거)
//   designer_nickname도 매칭된 계정의 현재 닉네임으로 정리 — 원문(핸들/괄호 등)이 남아있으면
//   character.html의 레거시 leftover 추출 로직이 다시 Site-OFF로 표시해버리기 때문.
// 122(북북), 123(익쟌)은 계정을 찾지 못해 사이트오프로 그대로 둡니다 — 이 스크립트는 건드리지 않음.
(async () => {
  const APPLY_LIST = [
    { character_id: 5106, name: '아기융용-124', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5107, name: '아기융용-125', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5108, name: '아기융용-126', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5110, name: '아기융용-128', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5111, name: '아기융용-129', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5112, name: '아기융용-130', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5113, name: '아기융용-131', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5118, name: '아기융용-136', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5119, name: '아기융용-137', designer_user_ids: ['9e8502f3-5577-46eb-bc3f-23bc5b70d033'], designer_nickname: '유떡' },
    { character_id: 5115, name: '아기융용-133', designer_user_ids: ['f4431d3e-8839-48db-8de1-a170e2920536'], designer_nickname: '엠제이' },
    { character_id: 5116, name: '아기융용-134', designer_user_ids: ['f4431d3e-8839-48db-8de1-a170e2920536'], designer_nickname: '엠제이' },
    { character_id: 5117, name: '아기융용-135', designer_user_ids: ['81e2ed2a-a227-4164-b875-015e04b16e6c'], designer_nickname: '챨' },
    { character_id: 5114, name: '아기융용-132', designer_user_ids: ['5b31c7c2-575d-46a9-803b-937898e4e081'], designer_nickname: '사월巳月' },
  ];

  console.log('총', APPLY_LIST.length, '건 반영 시작 (122/123은 사이트오프 유지, 대상 아님)');
  let done = 0, failed = [];
  for (const item of APPLY_LIST) {
    const { error } = await sb.from('characters').update({
      designer_user_ids: item.designer_user_ids,
      designer_external: [],
      designer_nickname: item.designer_nickname,
    }).eq('id', item.character_id);
    if (error) { failed.push({ id: item.character_id, name: item.name, error: error.message }); }
    else done++;
  }
  console.log('완료:', done, '건 처리, 실패:', failed.length, '건');
  if (failed.length) console.log('실패 목록:', failed);
})();
