(async () => {
  const APPLY_LIST = [{"character_id":3870,"designer_user_ids":["1e283250-3bba-4b9d-8f7c-ac4e8f35eec6"],"designer_external":[],"designer_nickname":"견"},{"character_id":3474,"designer_user_ids":["2c0cd33c-d1d1-447c-88cf-a042d10b7458"],"designer_external":[],"designer_nickname":"plein"},{"character_id":3425,"designer_user_ids":["2c0cd33c-d1d1-447c-88cf-a042d10b7458"],"designer_external":[],"designer_nickname":"plein"},{"character_id":3343,"designer_user_ids":["2c0cd33c-d1d1-447c-88cf-a042d10b7458"],"designer_external":[],"designer_nickname":"plein"},{"character_id":3344,"designer_user_ids":["2c0cd33c-d1d1-447c-88cf-a042d10b7458"],"designer_external":[],"designer_nickname":"plein"},{"character_id":3397,"designer_user_ids":["1e283250-3bba-4b9d-8f7c-ac4e8f35eec6"],"designer_external":[],"designer_nickname":"견"},{"character_id":3398,"designer_user_ids":["1e283250-3bba-4b9d-8f7c-ac4e8f35eec6"],"designer_external":[],"designer_nickname":"견"},{"character_id":3716,"designer_user_ids":["abcf2387-1e9f-4af8-b5aa-09e2515f8849"],"designer_external":[],"designer_nickname":"버찌랑"},{"character_id":3817,"designer_user_ids":["1e283250-3bba-4b9d-8f7c-ac4e8f35eec6"],"designer_external":[],"designer_nickname":"견"}];
  console.log('총', APPLY_LIST.length, '건 반영 시작');
  let done = 0, failed = [];
  for (const item of APPLY_LIST) {
    const { error } = await sb.from('characters').update({
      designer_user_ids: item.designer_user_ids,
      designer_external: item.designer_external,
      designer_nickname: item.designer_nickname,
    }).eq('id', item.character_id);
    if (error) { failed.push({ id: item.character_id, error: error.message }); }
    done++;
  }
  console.log('완료:', done, '건 처리, 실패:', failed.length, '건');
  if (failed.length) console.log('실패 목록:', failed);
})();
