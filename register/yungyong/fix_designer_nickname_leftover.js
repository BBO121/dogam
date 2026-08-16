(async () => {
  const FIX_LIST = [
    { character_id: 4786, designer_nickname: '연구원 M' },
    { character_id: 4802, designer_nickname: 'CHO' },
    { character_id: 4818, designer_nickname: '엠제이' },
  ];
  console.log('총', FIX_LIST.length, '건 반영 시작');
  let done = 0, failed = [];
  for (const item of FIX_LIST) {
    const { error } = await sb.from('characters').update({
      designer_nickname: item.designer_nickname,
    }).eq('id', item.character_id);
    if (error) { failed.push({ id: item.character_id, error: error.message }); }
    done++;
  }
  console.log('완료:', done, '건 처리, 실패:', failed.length, '건');
  if (failed.length) console.log('실패 목록:', failed);
})();
