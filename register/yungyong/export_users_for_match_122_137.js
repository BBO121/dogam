// 아기융용-122 ~ 137 디자이너 매칭 "검수용" 데이터 추출 스크립트 (DB는 건드리지 않음)
// 관리자 로그인된 페이지의 브라우저 콘솔에 붙여넣어 실행하세요.
// 실행하면 결과 JSON이 클립보드에 복사됩니다. 그걸 그대로 클롱한테 붙여넣어 주세요.
(async () => {
  const NAMES = [];
  for (let n = 122; n <= 137; n++) NAMES.push(`아기융용-${n}`);

  const { data: users, error: userErr } = await sb.rpc('get_all_users_full');
  if (userErr) { console.error('사용자 조회 실패:', userErr.message); return; }

  const { data: chars, error: charErr } = await sb.from('characters')
    .select('id, name, designer_nickname, designer_user_ids')
    .eq('species_name', '융용')
    .in('name', NAMES);
  if (charErr) { console.error('개체 조회 실패:', charErr.message); return; }
  if (chars.length !== NAMES.length) {
    console.warn('찾은 개체 수가 예상과 달라요:', chars.length, '/', NAMES.length, chars.map(c => c.name));
  }

  const payload = {
    users: users.map(u => ({ id: u.id, nickname: u.nickname, login_id: u.login_id })),
    chars: chars.map(c => ({ id: c.id, name: c.name, designer_nickname: c.designer_nickname, designer_user_ids: c.designer_user_ids })),
  };
  const json = JSON.stringify(payload);

  try {
    await navigator.clipboard.writeText(json);
    console.log('클립보드에 복사했어요. 클롱한테 붙여넣어 주세요. (유저 ' + payload.users.length + '명, 개체 ' + payload.chars.length + '건)');
  } catch (e) {
    console.warn('클립보드 복사 실패, 아래 JSON을 직접 복사해주세요.');
    console.log(json);
  }
})();
