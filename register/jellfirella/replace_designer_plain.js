(async () => {
  const NEW_USER_ID = '2c0cd33c-d1d1-447c-88cf-a042d10b7458';

  const { data: users, error: userErr } = await sb.rpc('get_all_users');
  if (userErr) { console.error('사용자 조회 실패:', userErr.message); return; }
  const newUser = (users || []).find(u => u.id === NEW_USER_ID);
  if (!newUser) { console.error('해당 user_id를 찾을 수 없습니다:', NEW_USER_ID); return; }
  const newNick = newUser.nickname || newUser.login_id || '(닉네임 없음)';
  console.log('새 디자이너:', newNick, NEW_USER_ID);

  const { data: chars, error: charErr } = await sb.from('characters')
    .select('id, char_number, name, designer_user_ids, designer_external, designer_nickname')
    .eq('species_name', '젤피렐라');
  if (charErr) { console.error('개체 조회 실패:', charErr.message); return; }

  const targets = (chars || []).filter(c =>
    Array.isArray(c.designer_external) && c.designer_external.some(e => e && e.name === '플레인')
  );

  console.log(`대상 ${targets.length}건:`, targets.map(t => `#${t.char_number} ${t.name}`));

  let done = 0; const failed = [];
  for (const c of targets) {
    const remainingExternal = c.designer_external.filter(e => !(e && e.name === '플레인'));
    const existingIds = c.designer_user_ids || [];
    const newIds = existingIds.includes(NEW_USER_ID) ? existingIds : [...existingIds, NEW_USER_ID];

    const siteNicks = newIds.map(id => {
      if (id === NEW_USER_ID) return newNick;
      const u = (users || []).find(u => u.id === id);
      return u ? (u.nickname || u.login_id) : id;
    });
    const newNickname = [...siteNicks, ...remainingExternal.map(e => e.name)].join(' / ');

    const { error } = await sb.from('characters').update({
      designer_user_ids: newIds,
      designer_external: remainingExternal,
      designer_nickname: newNickname,
    }).eq('id', c.id);

    if (error) failed.push({ id: c.id, char_number: c.char_number, error: error.message });
    else done++;
  }

  console.log('완료:', done, '건 처리, 실패:', failed.length, '건');
  if (failed.length) console.log('실패 목록:', failed);
})();
