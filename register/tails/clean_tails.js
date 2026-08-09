const fs = require('fs');
const path = require('path');

const srcPath = path.join(__dirname, 'tails_0000_0028.json');
const outPath = path.join(__dirname, 'tails_0000_0028_clean.json');
const reportPath = path.join(__dirname, 'tails_0000_0028_validation_report.json');

const raw = JSON.parse(fs.readFileSync(srcPath, 'utf8'));

const issues = []; // ambiguous/notable items for manual review
const errors = []; // hard validation failures

function extractName(nameField, idx) {
  // name field format: "{실제이름}{YYYY년...}...{번호}.{실제이름}"
  // real name is everything before the first 4-digit-year token, trimmed.
  const m = nameField.match(/^(.*?)\d{4}년/);
  if (!m) {
    issues.push({ idx, field: 'name', note: '연도 패턴을 찾지 못해 이름을 분리하지 못함', raw: nameField });
    return nameField.trim();
  }
  return m[1].trim();
}

function extractClassification(bunryuField, idx) {
  // format: "데비스[능력:...]...최근 게시물..." or "에니스[능력:...]..."
  const idxBracket = bunryuField.indexOf('[');
  if (idxBracket === -1) {
    issues.push({ idx, field: '분류', note: "'[' 마커를 찾지 못함", raw: bunryuField });
    return bunryuField.trim();
  }
  return bunryuField.slice(0, idxBracket).trim();
}

function extractDescription(descField, idx) {
  const marker = '최근 게시물';
  const at = descField.indexOf(marker);
  if (at === -1) {
    issues.push({ idx, field: 'description', note: "'최근 게시물' 마커를 찾지 못함 (그대로 유지)", raw: descField });
    return descField.trim();
  }
  return descField.slice(0, at).trimEnd();
}

const cleaned = raw.map((item, idx) => {
  const name = extractName(item.name, idx);
  const 분류 = extractClassification(item.custom_field_values['분류'], idx);
  const description = extractDescription(item.description, idx);
  const 주식 = item.custom_field_values['주식']; // 이미 분리되어 있음, 원문 보존
  const 능력 = item.custom_field_values['능력']; // 이미 분리되어 있음, 원문 보존

  // name/주식 표기 불일치 등 참고용 노트 (수정하지 않음)
  if (name.replace(/\s+/g, '').replace(/의테일스$/, '') !== 주식.replace(/\s+/g, '')) {
    issues.push({
      idx,
      field: 'name vs 주식',
      note: '이름과 주식 표기가 정확히 일치하지 않음 (원문 그대로 보존, 확인 필요)',
      name,
      주식,
    });
  }

  return {
    name,
    species_name: item.species_name,
    char_number: item.char_number,
    owner_nickname: item.owner_nickname,
    owner_user_id: item.owner_user_id,
    owner_is_offsite: item.owner_is_offsite,
    designer_nickname: item.designer_nickname,
    designer_user_ids: item.designer_user_ids,
    custom_field_values: {
      주식,
      분류,
      능력,
    },
    description,
    source_url: item.source_url,
  };
});

// ---- 수동 보정 (뽀 확인 후 승인된 항목만) ----
// 1) 0009 owner_nickname: 원문에 닫는 괄호가 누락되어 있어 보정
// 2) 능력 필드: "[능력:...]" 괄호 파싱 과정에서 사라진 절 구분 공백을 복원
//    (전부 "~하는 능력" + 다음 절이 공백 없이 붙어버린 동일한 원인의 붙어쓰기)
const manualFixes = {
  '0028': { 능력: ['능력본체의', '능력 본체의'] },
  '0027': { 능력: ['능력본체의', '능력 본체의'] },
  '0026': { 능력: ['능력아무리', '능력 아무리'] },
  '0023': { 능력: ['능력아무리', '능력 아무리'] },
  '0022': { 능력: ['능력주로', '능력 주로'] },
  '0021': { 능력: ['능력아무리', '능력 아무리'] },
  '0020': { 능력: ['능력매우', '능력 매우'] },
  '0019': { 능력: ['능력매우', '능력 매우'] },
  '0018': { 능력: ['능력능력으로', '능력 능력으로'] },
  '0017': { 능력: ['공격한다초코볼이라', '공격한다 초코볼이라'] },
  '0016': { 능력: ['능력본체', '능력 본체'] },
  '0014': { 능력: ['만든다주로', '만든다 주로'] },
  '0013': { 능력: ['능력강력한', '능력 강력한'] },
  '0012': { 능력: ['능력먹은', '능력 먹은'] },
  '0011': { 능력: ['능력식물이나', '능력 식물이나'] },
  '0010': { 능력: ['능력액체가', '능력 액체가'] },
  '0009': {
    능력: ['능력꼬리에', '능력 꼬리에'],
    owner_nickname: ['99(구구/뀨', '99(구구/뀨)'],
  },
  '0008': { 능력: ['능력자신의', '능력 자신의'] },
  '0007': { 능력: ['능력빛을', '능력 빛을'] },
  '0006': { 능력: ['능력비눗방울을', '능력 비눗방울을'] },
  '0005': { 능력: ['능력하루에', '능력 하루에'] },
  '0004': { 능력: ['능력하루에', '능력 하루에'] },
  '0003': { 능력: ['능력하루에', '능력 하루에'] },
  '0002': { 능력: ['능력하루에', '능력 하루에'] },
  '0001': { 능력: ['능력하루에', '능력 하루에'] },
};

const appliedFixes = [];
cleaned.forEach((item) => {
  const fix = manualFixes[item.char_number];
  if (!fix) return;
  if (fix.능력) {
    const [from, to] = fix.능력;
    if (!item.custom_field_values['능력'].includes(from)) {
      errors.push(`char_number=${item.char_number}: 능력 보정 대상 문자열("${from}")을 찾지 못함`);
    } else {
      item.custom_field_values['능력'] = item.custom_field_values['능력'].replace(from, to);
      appliedFixes.push({ char_number: item.char_number, field: '능력', from, to });
    }
  }
  if (fix.owner_nickname) {
    const [from, to] = fix.owner_nickname;
    if (item.owner_nickname !== from) {
      errors.push(`char_number=${item.char_number}: owner_nickname 보정 대상("${from}")과 불일치, 현재값="${item.owner_nickname}"`);
    } else {
      item.owner_nickname = to;
      appliedFixes.push({ char_number: item.char_number, field: 'owner_nickname', from, to });
    }
  }
});

// ---- 검증 ----
const seenNumbers = new Set();
cleaned.forEach((item, idx) => {
  const ctx = `#${idx} (char_number=${item.char_number})`;

  if (!/^\d{4}$/.test(item.char_number)) {
    errors.push(`${ctx}: char_number가 4자리 숫자 문자열이 아님: "${item.char_number}"`);
  } else if (seenNumbers.has(item.char_number)) {
    errors.push(`${ctx}: char_number 중복`);
  } else {
    seenNumbers.add(item.char_number);
  }

  if (item.species_name !== '테일스') {
    errors.push(`${ctx}: species_name이 "테일스"가 아님: "${item.species_name}"`);
  }

  if (!item.name || /\d{4}년|최근 게시물|최종 수정일/.test(item.name)) {
    errors.push(`${ctx}: name에 노이즈가 남아있거나 비어있음: "${item.name}"`);
  }

  if (item.owner_user_id !== null) {
    errors.push(`${ctx}: owner_user_id가 null이 아님`);
  }
  if (item.owner_is_offsite !== true) {
    errors.push(`${ctx}: owner_is_offsite가 true가 아님`);
  }
  if (item.designer_nickname !== '슷큐') {
    errors.push(`${ctx}: designer_nickname이 "슷큐"가 아님`);
  }
  if (!Array.isArray(item.designer_user_ids) || item.designer_user_ids[0] !== '3b060ba1-64cb-4eb3-8289-1ff9a88add8e') {
    errors.push(`${ctx}: designer_user_ids가 예상 UUID와 다름`);
  }

  const cfv = item.custom_field_values;
  const keys = Object.keys(cfv);
  if (keys.length !== 3 || !keys.includes('주식') || !keys.includes('분류') || !keys.includes('능력')) {
    errors.push(`${ctx}: custom_field_values 키 구성이 예상과 다름: ${keys.join(',')}`);
  }
  if (!cfv['주식']) errors.push(`${ctx}: 주식 값이 비어있음`);
  if (!['데비스', '에니스'].includes(cfv['분류'])) {
    errors.push(`${ctx}: 분류 값이 "데비스"/"에니스"가 아님: "${cfv['분류']}"`);
  }
  if (!cfv['능력'] || /최근 게시물|\[능력/.test(cfv['능력'])) {
    errors.push(`${ctx}: 능력 값이 비어있거나 노이즈 포함: "${cfv['능력']}"`);
  }
  if (/\[능력:|최근 게시물|전체 보기/.test(cfv['분류'])) {
    errors.push(`${ctx}: 분류에 노이즈 잔존: "${cfv['분류']}"`);
  }

  if (!item.description || /최근 게시물|전체 보기|\[능력:/.test(item.description)) {
    errors.push(`${ctx}: description에 노이즈가 남아있거나 비어있음`);
  }

  if (!item.source_url || !item.source_url.startsWith('https://sq1222.wixsite.com/tails/post/')) {
    errors.push(`${ctx}: source_url이 예상 패턴과 다름: "${item.source_url}"`);
  }
});

// 0000~0028 전체 존재 확인
for (let i = 0; i <= 28; i++) {
  const num = String(i).padStart(4, '0');
  if (!seenNumbers.has(num)) {
    errors.push(`char_number ${num} 누락`);
  }
}

fs.writeFileSync(outPath, JSON.stringify(cleaned, null, 2), 'utf8');
fs.writeFileSync(
  reportPath,
  JSON.stringify({ total: cleaned.length, errors, issues, appliedFixes }, null, 2),
  'utf8'
);

console.log('총 개체 수:', cleaned.length);
console.log('오류(errors):', errors.length);
console.log('참고 목록(issues):', issues.length);
console.log('적용된 수동 보정(appliedFixes):', appliedFixes.length);
if (errors.length) {
  console.log('\n--- ERRORS ---');
  errors.forEach((e) => console.log(' -', e));
}
if (issues.length) {
  console.log('\n--- ISSUES (참고) ---');
  issues.forEach((i) => console.log(' -', JSON.stringify(i)));
}
if (appliedFixes.length) {
  console.log('\n--- APPLIED FIXES ---');
  appliedFixes.forEach((f) => console.log(' -', JSON.stringify(f)));
}
