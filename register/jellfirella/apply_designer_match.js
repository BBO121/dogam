(async () => {
  const APPLY_LIST = [{"character_id":4017,"designer_user_ids":["1e283250-3bba-4b9d-8f7c-ac4e8f35eec6"],"designer_external":[],"designer_nickname":"견"},{"character_id":4614,"designer_user_ids":["f4431d3e-8839-48db-8de1-a170e2920536"],"designer_external":[],"designer_nickname":"엠제이"},{"character_id":4128,"designer_user_ids":["587d5b96-15f4-4e95-8ce9-e0c8575e215f"],"designer_external":[],"designer_nickname":"오캉"},{"character_id":4281,"designer_user_ids":["55fe9213-b7ce-4bea-87f4-102d961874ea"],"designer_external":[],"designer_nickname":"넷지"},{"character_id":4307,"designer_user_ids":["38b83923-ee4d-4157-88c8-5f909cfb0778"],"designer_external":[],"designer_nickname":"M4CH1N4"},{"character_id":4305,"designer_user_ids":["38b83923-ee4d-4157-88c8-5f909cfb0778"],"designer_external":[],"designer_nickname":"M4CH1N4"},{"character_id":4306,"designer_user_ids":["38b83923-ee4d-4157-88c8-5f909cfb0778"],"designer_external":[],"designer_nickname":"M4CH1N4"},{"character_id":4615,"designer_user_ids":["7b3deebd-0c37-4c13-963a-7b27108502c4"],"designer_external":[],"designer_nickname":"언쿠"},{"character_id":4624,"designer_user_ids":["6d29c889-1a37-4f7b-996d-073fdb688063"],"designer_external":[],"designer_nickname":"티스"},{"character_id":4581,"designer_user_ids":["38b83923-ee4d-4157-88c8-5f909cfb0778"],"designer_external":[],"designer_nickname":"M4CH1N4"},{"character_id":4616,"designer_user_ids":["fe5c29dc-2aff-434c-8cc5-050026671023"],"designer_external":[],"designer_nickname":"쥬엘"},{"character_id":4670,"designer_user_ids":["fe5c29dc-2aff-434c-8cc5-050026671023"],"designer_external":[],"designer_nickname":"쥬엘"},{"character_id":4672,"designer_user_ids":["fe5c29dc-2aff-434c-8cc5-050026671023"],"designer_external":[],"designer_nickname":"쥬엘"},{"character_id":4671,"designer_user_ids":["fe5c29dc-2aff-434c-8cc5-050026671023"],"designer_external":[],"designer_nickname":"쥬엘"},{"character_id":4673,"designer_user_ids":["fe5c29dc-2aff-434c-8cc5-050026671023"],"designer_external":[],"designer_nickname":"쥬엘"},{"character_id":4623,"designer_user_ids":["84aaad7a-9e65-416d-a3ea-e1c7ed896964"],"designer_external":[],"designer_nickname":"CHO"}];
  let done = 0; const failed = [];
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
