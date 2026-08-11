(async () => {
  const CHAR_ID = 3777;
  const { data: c } = await sb.from('characters')
    .select('image_url, thumbnail_url, original_image_url, representative_step_id')
    .eq('id', CHAR_ID).single();
  const { data: step } = await sb.from('character_step_images')
    .select('id, species_step_id, image_url, thumbnail_url, original_image_url')
    .eq('character_id', CHAR_ID).eq('species_step_id', 53) // 아기융
    .single();

  if (!c || !step) { console.error('데이터를 찾을 수 없어요', c, step); return; }

  const { error: e1 } = await sb.from('characters').update({
    image_url: step.image_url,
    thumbnail_url: step.thumbnail_url,
    original_image_url: step.original_image_url,
  }).eq('id', CHAR_ID);

  const { error: e2 } = await sb.from('character_step_images').update({
    image_url: c.image_url,
    thumbnail_url: c.thumbnail_url,
    original_image_url: c.original_image_url,
  }).eq('id', step.id);

  if (e1 || e2) console.error('실패:', e1, e2);
  else console.log('✅ 발탁용 ↔ 아기융 이미지 교체 완료');
})();
