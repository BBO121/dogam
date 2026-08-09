// 사용법: node clean_tails_generic.js <raw.json> <out_clean.json> <out_report.json> <rangeStart> <rangeEnd>
// raw.json: [{ number: "101", url: "https://...", text: "<WebFetch 검증용 원문 그대로 dump>" }, ...]

const fs = require('fs');

const [, , srcPath, outPath, reportPath, rangeStartArg, rangeEndArg] = process.argv;
if (!srcPath || !outPath || !reportPath) {
  console.error('사용법: node clean_tails_generic.js <raw.json> <out_clean.json> <out_report.json> [rangeStart] [rangeEnd]');
  process.exit(1);
}

const rangeStart = rangeStartArg ? parseInt(rangeStartArg, 10) : null;
const rangeEnd = rangeEndArg ? parseInt(rangeEndArg, 10) : null;

const raw = JSON.parse(fs.readFileSync(srcPath, 'utf8'));

const issues = [];
const errors = [];

const DESIGNER_NICKNAME = '슷큐';
const DESIGNER_USER_IDS = ['3b060ba1-64cb-4eb3-8289-1ff9a88add8e'];

function parseDump(rawText, ctx) {
  const result = { name: null, owner: null, 주식: null, 분류: null, 능력: null, description: null };

  // 마크다운 잔여물 제거: 굵게(**) 표시, 줄 앞의 '#' 헤딩 마커
  const text = rawText
    .split('\n')
    .map((l) => l.replace(/^\s*#+\s*/, ''))
    .join('\n')
    .replace(/\*\*/g, '');
  const lines = text.split('\n').map((l) => l.trim());

  // '최근 게시물' 이후(하단 추천글 목록)에는 다른 번호가 섞여 나오므로 제목 탐색 범위에서 제외
  const recentPostsIdx = lines.findIndex((l) => l.startsWith('최근 게시물'));
  const searchLines = recentPostsIdx === -1 ? lines : lines.slice(0, recentPostsIdx);

  const titleCandidates = searchLines.filter((l) => /^\d+\.(.+)$/.test(l));
  // "...의 테일스"로 끝나는(파트너 표기가 붙어도 됨) 줄이 가장 신뢰도 높은 제목이므로 최우선
  let titleLine =
    titleCandidates.find((l) => /의\s*테일스\s*(\(.*)?$/.test(l)) ||
    titleCandidates.find((l) => !l.includes('파트너')) ||
    titleCandidates[0];
  if (titleLine) {
    const titleParts = titleLine.match(/^(\d+)\.(.+)$/);
    result.embeddedNumber = titleParts[1].padStart(4, '0');
    let nm = titleParts[2].trim();
    nm = nm.replace(/\s*\(\s*파트너[\s\S]*$/, '').trim();
    // WebFetch가 자체적으로 붙이는 안내문구(영문/한글) 잔여물 제거
    nm = nm.replace(/\s*-\s*(Full\s+)?(Visible\s+)?(Page\s+)?(Body\s+)?(Text|Content)$/i, '').trim();
    nm = nm.replace(/\s*(페이지\s*)?전문(\s*내용)?$/, '').trim();
    result.name = nm;
    if (!/의\s*테일스$/.test(nm)) {
      issues.push({ ctx, field: 'name', note: `name이 "의 테일스"로 끝나지 않음, 확인 필요: "${nm}"` });
    }
  } else {
    issues.push({ ctx, field: 'name', note: '제목 라인을 찾지 못함', raw: lines[0] });
  }

  // 대부분 "파트너"지만, 테마에 따라 "계약자" 등 다른 호칭을 쓰는 개체도 있음
  const OWNER_LABELS = '파트너|계약자|전언자';
  const ownerMatch = text.match(new RegExp(`\\(\\s*(?:${OWNER_LABELS})[:：]?\\s*([^)]+?)\\s*\\)`));
  if (ownerMatch) {
    result.owner = ownerMatch[1].replace(/님\s*$/, '').trim();
  } else {
    // 변형 형태: 괄호 없이 "파트너: X" / "파트너: X 님" 한 줄로 오는 경우
    const ownerLineMatch = text.match(new RegExp(`(?:${OWNER_LABELS})[:：]\\s*([^\\n]+)`));
    if (ownerLineMatch) {
      result.owner = ownerLineMatch[1].replace(/님\s*$/, '').trim();
      issues.push({ ctx, field: 'owner', note: '괄호 없는 변형 포맷에서 파트너명을 추출함 (확인 권장)' });
    } else {
      issues.push({ ctx, field: 'owner', note: "'파트너: ...' 패턴을 찾지 못함" });
    }
  }

  const jushikMatch = text.match(/주식[:：]\s*([^\n/]+)\/([^\n[]+)/);
  if (jushikMatch) {
    result.주식 = jushikMatch[1].trim();
    result.분류 = jushikMatch[2].trim();
  } else {
    issues.push({ ctx, field: '주식/분류', note: '주식:X/Y 패턴을 찾지 못함' });
  }

  // 정상 형태: [능력:CONTENT]
  const abilityMatch = text.match(/\[능력[:：]\s*([\s\S]*?)\]/);
  let abilityEnd = null;
  if (abilityMatch && abilityMatch[1].trim()) {
    result.능력 = abilityMatch[1].replace(/\s+/g, ' ').trim();
    abilityEnd = text.indexOf(abilityMatch[0]) + abilityMatch[0].length;
  } else {
    // 변형 형태: [능력:] 또는 [능력]: 처럼 대괄호 안이 비어있고 내용이 바깥에 있는 경우
    const brokenMatch = text.match(/\[\s*능력\s*[:：]?\s*\]\s*[:：]?\s*/);
    if (brokenMatch) {
      const afterBroken = text.slice(text.indexOf(brokenMatch[0]) + brokenMatch[0].length);
      const blankIdx = afterBroken.search(/\n\s*\n/);
      const abilityText = blankIdx === -1 ? afterBroken : afterBroken.slice(0, blankIdx);
      result.능력 = abilityText.replace(/\s+/g, ' ').trim();
      abilityEnd = text.indexOf(brokenMatch[0]) + brokenMatch[0].length + (blankIdx === -1 ? afterBroken.length : blankIdx);
      issues.push({ ctx, field: '능력', note: '대괄호가 비어있는 변형 포맷이라 괄호 밖 텍스트를 능력으로 사용함 (확인 권장)' });
    } else {
      // 닫는 대괄호 ']' 자체가 원문에 없는 경우: 첫 문단을 능력으로, 이후를 설명으로 취급
      const openMatch = text.match(/\[\s*능력\s*[:：]\s*/);
      if (openMatch) {
        const afterOpen = text.slice(text.indexOf(openMatch[0]) + openMatch[0].length);
        const blankIdx = afterOpen.search(/\n\s*\n/);
        const abilityText = blankIdx === -1 ? afterOpen : afterOpen.slice(0, blankIdx);
        result.능력 = abilityText.replace(/\s+/g, ' ').trim();
        abilityEnd = text.indexOf(openMatch[0]) + openMatch[0].length + (blankIdx === -1 ? afterOpen.length : blankIdx);
        issues.push({ ctx, field: '능력', note: "원문에 닫는 대괄호 ']'가 없어 첫 문단을 능력으로 간주함 (원문 자체 누락, 확인 권장)" });
      } else {
        issues.push({ ctx, field: '능력', note: '[능력:...] 패턴을 찾지 못함' });
      }
    }
  }

  if (abilityEnd !== null) {
    const afterAbility = text.slice(abilityEnd);
    const marker = '최근 게시물';
    const at = afterAbility.indexOf(marker);
    const descBlock = at === -1 ? afterAbility : afterAbility.slice(0, at);
    if (at === -1) {
      issues.push({ ctx, field: 'description', note: "'최근 게시물' 마커를 찾지 못함 (그대로 유지)" });
    }
    const paragraphs = descBlock
      .split(/\n{2,}/)
      .map((p) => p.replace(/\s+/g, ' ').trim())
      .filter(Boolean);
    result.description = paragraphs.join('');
  }

  return result;
}

const cleaned = [];

raw.forEach((item, idx) => {
  if (!item.text) {
    issues.push({ ctx: `raw idx ${idx}`, field: 'crawl-error', note: '본문 텍스트 없음', raw: item });
    return;
  }
  const number = parseInt(item.number, 10);
  const char_number = String(number).padStart(4, '0');
  const ctx = `char_number=${char_number}`;

  const { name, owner, 주식, 분류, 능력, description, embeddedNumber } = parseDump(item.text, ctx);

  if (embeddedNumber && embeddedNumber !== char_number) {
    errors.push(`${ctx}: 페이지 제목에 실제 적힌 번호(${embeddedNumber})가 char_number(${char_number})와 다름 - URL/번호 매칭이 잘못됐을 가능성, 반드시 확인 필요`);
  }

  cleaned.push({
    name,
    species_name: '테일스',
    char_number,
    owner_nickname: owner,
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
  if (!cfv['주식']) issues.push({ ctx, field: '주식', note: '주식 값이 비어있음' });
  if (!['데비스', '에니스'].includes(cfv['분류'])) {
    issues.push({ ctx, field: '분류', note: `분류 값이 "데비스"/"에니스"가 아님(신규 분류일 수 있음, 확인 필요): "${cfv['분류']}"` });
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

if (rangeStart !== null && rangeEnd !== null) {
  for (let i = rangeStart; i <= rangeEnd; i++) {
    const num = String(i).padStart(4, '0');
    if (!seenNumbers.has(num)) {
      errors.push(`char_number ${num} 누락`);
    }
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
