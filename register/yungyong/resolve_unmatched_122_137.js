// 아기융용-122, 123, 132 디자이너 확인용 — admin/staff 전용 RPC라 관리자 로그인 콘솔에서 실행
// DB를 수정하지 않고 조회만 합니다. 결과를 클립보드에 복사하니 그대로 클롱한테 붙여넣어 주세요.
(async () => {
  const IDENTIFIERS = ['북북', 'bugbugcreature', '익쟌', 'rlesy521', '사월', 'D108772'];
  const { data, error } = await sb.rpc('resolve_users_by_identifiers', { p_identifiers: IDENTIFIERS });
  if (error) { console.error('조회 실패:', error.message); return; }
  console.log(data);
  try {
    await navigator.clipboard.writeText(JSON.stringify(data));
    console.log('클립보드에 복사했어요.');
  } catch (e) {
    console.warn('클립보드 복사 실패, 위 결과를 직접 복사해주세요.');
  }
})();
