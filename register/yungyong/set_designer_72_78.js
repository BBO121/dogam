(async () => {
  const TARGET_USER_ID = '9e8502f3-5577-46eb-bc3f-23bc5b70d033';
  const NAMES = ['아기융용-72', '아기융용-73', '아기융용-76', '아기융용-77', '아기융용-78'];

  const { data: users, error: userErr } = await sb.rpc('get_all_users_full');
  if (userErr) { console.error('사용자 조회 실패:', userErr.message); return; }
  const user = users.find(u => u.id === TARGET_USER_ID);
  if (!user) { console.error('해당 user_id를 찾지 못했어요:', TARGET_USER_ID); return; }
  console.log('디자이너로 지정할 유저:', user.nickname, `(${user.id})`);

  const { data: chars, error: charErr } = await sb.from('characters')
    .select('id, name')
    .eq('species_name', '융용')
    .in('name', NAMES);
  if (charErr) { console.error('개체 조회 실패:', charErr.message); return; }
  if (chars.length !== NAMES.length) {
    console.warn('찾은 개체 수가 예상과 달라요:', chars.length, '/', NAMES.length, chars);
  }

  console.log('총', chars.length, '건 반영 시작');
  let done = 0, failed = [];
  for (const c of chars) {
    const { error } = await sb.from('characters').update({
      designer_user_ids: [TARGET_USER_ID],
      designer_external: [],
      designer_nickname: user.nickname,
    }).eq('id', c.id);
    if (error) { failed.push({ id: c.id, name: c.name, error: error.message }); }
    done++;
  }
  console.log('완료:', done, '건 처리, 실패:', failed.length, '건');
  if (failed.length) console.log('실패 목록:', failed);
})();
