const fs = require('fs');
const path = require('path');

const srcPath = path.join(__dirname, 'tails_0029_0100.json');
const outPath = path.join(__dirname, 'tails_0029_0100_clean.json');
const reportPath = path.join(__dirname, 'tails_0029_0100_validation_report.json');

const raw = JSON.parse(fs.readFileSync(srcPath, 'utf8'));

const issues = []; // 검토 필요 / 참고용
const errors = []; // 하드 검증 실패

const DESIGNER_NICKNAME = '슷큐';
const DESIGNER_USER_IDS = ['3b060ba1-64cb-4eb3-8289-1ff9a88add8e'];

function extractName(nameField, ctx) {
  // "{실제이름}{YYYY년...}...{번호}.{실제이름}" 형태에서 첫 4자리 연도 앞부분을 이름으로 취급
  const m = nameField.match(/^(.*?)\d{4}년/);
  if (!m) {
    issues.push({ ctx, field: 'name', note: '연도 패턴을 찾지 못해 이름을 분리하지 못함', raw: nameField });
    return nameField.trim();
  }
  return m[1].trim();
}

function decodeSlugName(url, ctx) {
  try {
    const seg = url.split('/post/')[1] || '';
    const decoded = decodeURIComponent(seg);
    // "100-야채호빵의-테일스" -> "야채호빵의 테일스"
    const withoutNum = decoded.replace(/^\d+-/, '');
    return withoutNum.replace(/-/g, ' ').trim();
  } catch (e) {
    issues.push({ ctx, field: 'url', note: 'URL slug 디코딩 실패', raw: url });
    return null;
  }
}

function parseTextBody(text, ctx) {
  const result = { 주식: null, 분류: null, 능력: null, description: null };

  const m = text.match(/주식[:：]\s*([^/]*)\/([^[]*)\[능력[:：]\s*([\s\S]*?)\]([\s\S]*)/);
  if (!m) {
    errors.push(`${ctx}: 주식/분류/[능력:...] 패턴을 찾지 못함`);
    return result;
  }

  result.주식 = m[1].trim();
  result.분류 = m[2].trim();
  result.능력 = m[3].trim();

  const rest = m[4];
  const marker = '최근 게시물';
  const at = rest.indexOf(marker);
  if (at === -1) {
    issues.push({ ctx, field: 'description', note: "'최근 게시물' 마커를 찾지 못함 (그대로 유지)", raw: rest });
    result.description = rest.trim();
  } else {
    result.description = rest.slice(0, at).trim();
  }

  return result;
}

const cleaned = [];

raw.forEach((item, idx) => {
  if (item.error) {
    // 57번 실패 항목: 아래에서 수동 데이터로 별도 삽입 (스킵)
    issues.push({ ctx: `raw idx ${idx}`, field: 'crawl-error', note: '크롤링 실패 항목 - 수동 보충 데이터로 대체 예정', raw: item });
    return;
  }

  const number = parseInt(item.number, 10);
  const char_number = String(number).padStart(4, '0');
  const ctx = `char_number=${char_number}`;

  const name = extractName(item.name, ctx);
  const { 주식, 분류, 능력, description } = parseTextBody(item.text, ctx);

  const slugName = decodeSlugName(item.url, ctx);
  if (slugName && name) {
    const normalizedName = name.replace(/\s+/g, '').replace(/의테일스$/, '');
    const normalizedSlug = slugName.replace(/\s+/g, '').replace(/의테일스$/, '').replace(/테일스$/, '');
    if (normalizedSlug && !normalizedSlug.includes(normalizedName) && !normalizedName.includes(normalizedSlug)) {
      issues.push({
        ctx,
        field: 'name vs url-slug',
        note: '제목/본문 개체명과 URL slug가 서로 다름 (검토 필요, 임의 수정하지 않음)',
        name,
        url: item.url,
        slugName,
      });
    }
  }

  if (name && 주식) {
    const normalizedName = name.replace(/\s+/g, '').replace(/의테일스$/, '');
    const normalizedJushik = 주식.replace(/\s+/g, '');
    if (normalizedName !== normalizedJushik) {
      issues.push({
        ctx,
        field: 'name vs 주식',
        note: '이름과 주식 표기가 정확히 일치하지 않음 (원문 그대로 보존, 확인 필요)',
        name,
        주식,
      });
    }
  }

  if (item.owner === DESIGNER_NICKNAME) {
    issues.push({
      ctx,
      field: 'owner_nickname',
      note: 'owner_nickname이 designer_nickname(슷큐)과 동일함 - 실제 파트너 추출이 안됐을 가능성, 검토 필요',
      owner: item.owner,
    });
  }

  cleaned.push({
    name,
    species_name: '테일스',
    char_number,
    owner_nickname: item.owner,
    owner_user_id: null,
    owner_is_offsite: true,
    designer_nickname: DESIGNER_NICKNAME,
    designer_user_ids: DESIGNER_USER_IDS,
    custom_field_values: {
      주식,
      분류,
      능력,
    },
    description,
    source_url: item.url,
  });
});

// ---- 0057 수동 보충 ----
cleaned.push({
  name: '환상의 테일스',
  species_name: '테일스',
  char_number: '0057',
  owner_nickname: '감청',
  owner_user_id: null,
  owner_is_offsite: true,
  designer_nickname: DESIGNER_NICKNAME,
  designer_user_ids: DESIGNER_USER_IDS,
  custom_field_values: {
    주식: null,
    분류: null,
    능력:
      '현실을 환상으로 채워주는 능력. 일시적으로 현실을 잊고, 자신의 망상속에 빠질 수 있게 도와준다. 아픈 기억을 극복할 때, 큰 도움이 된다.',
  },
  description:
    '꿈 속의 이야기처럼 신비롭고 몽환적인 테일스, 비록 터무니없을지라도, 아름다운 비현실을 사랑하고 있다. 시간이 지날 수록, 사람들은 환상이 거짓됨을 깨닫고 현실로 돌아온다. 색을 잃은 사람들의 기억은 사무치게 외로웠다. 그 때 맛보았던 아름다운 환상을 한 번 더 만날 수 있을까? 평생토록 환상의 세계를 그리워하고 있다.\n\n*디자인권을 사용하여 창작한 테일스 입니다.',
  source_url: 'https://sq1222.wixsite.com/tails/post/57-%ED%99%98%EC%83%81%EC%9D%98-%ED%85%8C%EC%9D%BC%EC%8A%A4',
});
issues.push({
  ctx: 'char_number=0057',
  field: '주식/분류',
  note: '원문에 주식/분류 정보가 없어 null로 둠 (임의로 추측하지 않음) - 검증 필요 항목',
});

cleaned.sort((a, b) => a.char_number.localeCompare(b.char_number));

// ---- 검증 ----
const seenNumbers = new Set();
cleaned.forEach((item) => {
  const ctx = `char_number=${item.char_number}`;

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

  if (!item.owner_nickname) {
    errors.push(`${ctx}: owner_nickname이 비어있음`);
  }
  if (item.owner_user_id !== null) {
    errors.push(`${ctx}: owner_user_id가 null이 아님`);
  }
  if (item.owner_is_offsite !== true) {
    errors.push(`${ctx}: owner_is_offsite가 true가 아님`);
  }
  if (item.designer_nickname !== DESIGNER_NICKNAME) {
    errors.push(`${ctx}: designer_nickname이 "슷큐"가 아님`);
  }
  if (
    !Array.isArray(item.designer_user_ids) ||
    item.designer_user_ids.length !== 1 ||
    item.designer_user_ids[0] !== DESIGNER_USER_IDS[0]
  ) {
    errors.push(`${ctx}: designer_user_ids가 예상 UUID와 다름`);
  }

  const cfv = item.custom_field_values;
  const keys = Object.keys(cfv);
  if (keys.length !== 3 || !keys.includes('주식') || !keys.includes('분류') || !keys.includes('능력')) {
    errors.push(`${ctx}: custom_field_values 키 구성이 예상과 다름: ${keys.join(',')}`);
  }
  if (item.char_number !== '0057') {
    if (!cfv['주식']) errors.push(`${ctx}: 주식 값이 비어있음`);
    if (!['데비스', '에니스'].includes(cfv['분류'])) {
      errors.push(`${ctx}: 분류 값이 "데비스"/"에니스"가 아님: "${cfv['분류']}"`);
    }
  }
  if (!cfv['능력'] || /최근 게시물|\[능력/.test(cfv['능력'])) {
    errors.push(`${ctx}: 능력 값이 비어있거나 노이즈 포함: "${cfv['능력']}"`);
  }

  if (!item.description || /최근 게시물|전체 보기|\[능력:/.test(item.description)) {
    errors.push(`${ctx}: description에 노이즈가 남아있거나 비어있음`);
  }

  if (!item.source_url || !item.source_url.startsWith('https://sq1222.wixsite.com/tails/post/')) {
    errors.push(`${ctx}: source_url이 예상 패턴과 다름: "${item.source_url}"`);
  }
});

// 0029~0100 전체 존재 확인
for (let i = 29; i <= 100; i++) {
  const num = String(i).padStart(4, '0');
  if (!seenNumbers.has(num)) {
    errors.push(`char_number ${num} 누락`);
  }
}

fs.writeFileSync(outPath, JSON.stringify(cleaned, null, 2), 'utf8');
fs.writeFileSync(
  reportPath,
  JSON.stringify({ total: cleaned.length, errors, issues }, null, 2),
  'utf8'
);

console.log('총 개체 수:', cleaned.length);
console.log('오류(errors):', errors.length);
console.log('참고/검토 목록(issues):', issues.length);
if (errors.length) {
  console.log('\n--- ERRORS ---');
  errors.forEach((e) => console.log(' -', e));
}
if (issues.length) {
  console.log('\n--- ISSUES (참고/검토 필요) ---');
  issues.forEach((i) => console.log(' -', JSON.stringify(i)));
}
