const fs = require('fs');
const path = require('path');

const raw = fs.readFileSync(path.join(__dirname, '..', 'jellfirella_raw_gen3.txt'), 'utf-8');

const DEFAULT_DESIGNER_ID = '4eebcb25-f03b-4d8e-a020-6fc2f16cfacc';

// 개체 리스트 시작 지점부터만 사용 (인트로 텍스트 제외)
const listStart = raw.indexOf('[401]');
const body = raw.slice(listStart);

const markerRe = /^(\*?)\[(\d+)\]/gm;
const markers = [];
let m;
while ((m = markerRe.exec(body))) {
  markers.push({ star: m[1] === '*', num: m[2], start: m.index });
}

const entries = [];
for (let i = 0; i < markers.length; i++) {
  const cur = markers[i];
  const end = i + 1 < markers.length ? markers[i + 1].start : body.length;
  const block = body.slice(cur.start, end);
  entries.push({ star: cur.star, num: cur.num.padStart(3, '0'), block });
}

const daDesignerApplied = [];
const issues = [];
const parsed = [];

for (const e of entries) {
  const lines = e.block.split(/\r?\n/);
  // 첫 줄: [번호] 헤더 텍스트
  let headerLine = lines[0].replace(/^\*?\[\d+\]\s*/, '').trim();
  const restLines = lines.slice(1);

  let name = null, poison = null, owner_nickname = null;

  // 429 특이 케이스: 괄호 2개(이중 인격/이중 독), 하드코딩 처리
  if (e.num === '429') {
    name = '세룸 해파리 - 루미나레&움브라';
    poison = '루미나레(섬광독)&움브라(암흑독)';
    const ownerMatch = headerLine.match(/[‘']([^’']*)[’']/);
    owner_nickname = ownerMatch ? ownerMatch[1] : null;
  } else {
    const headerMatch = headerLine.match(/^(.*?)\(([^)]*)\)\s*-\s*[‘']([^’']*)[’']/);
    if (headerMatch) {
      name = headerMatch[1].trim();
      poison = headerMatch[2].trim();
      owner_nickname = headerMatch[3].trim();
      if (owner_nickname === '') owner_nickname = null;
    } else {
      // 괄호/따옴표 패턴이 아예 없는 경우 (예: 511) - 헤더 텍스트를 이름으로만 사용
      name = headerLine.trim() || null;
    }
  }

  // 나머지 줄에서 디자이너 크레딧(~님 DA/D), 무료분양 메모 등을 분리하고 description 조립
  const descParts = [];
  let freeAdoption = false;
  for (const raw_line of restLines) {
    const line = raw_line.trim();
    if (line === '') continue;
    const daMatch = line.match(/^(.+?)님\s*D(A)?$/);
    if (daMatch && line.length < 20) {
      daDesignerApplied.push({ char_number: e.num, designer: daMatch[1], raw: line });
      continue;
    }
    if (line === '무료분양 개체입니다.') { freeAdoption = true; continue; }
    if (line.startsWith('(') && line.includes(':')) { descParts.push(line); continue; } // 이름 뜻풀이 등 괄호줄도 description에 포함
    descParts.push(line);
  }
  const description = descParts.length ? descParts.join(' ') : null;

  const star = e.star;
  let designer_nickname, designer_user_id, designer_is_site_user;

  const daHit = daDesignerApplied.find(d => d.char_number === e.num);
  if (daHit) {
    designer_nickname = daHit.designer;
    designer_user_id = null;
    designer_is_site_user = false;
  } else if (star) {
    designer_nickname = owner_nickname;
    designer_user_id = null;
    designer_is_site_user = false;
  } else {
    designer_nickname = '새';
    designer_user_id = DEFAULT_DESIGNER_ID;
    designer_is_site_user = true;
  }

  const entryObj = {
    char_number: e.num,
    star,
    name,
    poison,
    owner_nickname,
    designer_nickname,
    designer_user_id,
    designer_is_site_user,
    classification: '특수개체',
    description,
    image_local_path: `register/jellfirella/images/jellfi_${e.num}.png`,
  };

  parsed.push(entryObj);

  if (freeAdoption) {
    issues.push({ ctx: `char_number=${e.num}`, field: 'note', note: '원문에 "무료분양 개체입니다." 메모 있음(참고용, 데이터에는 영향 없음)' });
  }
}

// 407, 412: 소유주 공란 + description 없음
['407', '412'].forEach(n => {
  const x = parsed.find(p => p.char_number === n);
  issues.push({ ctx: `char_number=${n}`, field: 'owner/description', note: `원문 자체에 소유주(빈 따옴표)와 description이 전혀 없음. name="${x.name}", poison="${x.poison}". 뽀 확인 필요.` });
});

issues.push({
  ctx: 'char_number=407,412,447,463,476,547,553,568',
  field: 'owner',
  note: '원문에 소유주가 빈 따옴표(\'\')로 되어 있어 owner_nickname=null 처리함. 8건 모두 동일 패턴(미배정 슬롯으로 추정) — 뽀 확인 필요.',
});

issues.push({
  ctx: 'char_number=412',
  field: 'poison',
  note: '헤더 괄호 안 표기가 "무분" — 표준 6독도 아니고 다른 특수능력 텍스트와도 다름. "무독"의 오타로 추정되나 확정하지 않고 원문 그대로 보존함.',
});

issues.push({
  ctx: 'char_number=464',
  field: 'owner',
  note: '소유주 닉네임이 문자 그대로 "error" — 실제 닉네임인지 원문/사이트 오류로 인한 표기인지 확인 필요. 원문 그대로 보존함.',
});

issues.push({
  ctx: 'char_number=511',
  field: 'entity',
  note: '"[511] 키사라기역" — 이름(으로 추정되는 텍스트)만 있고 poison/owner/description이 전혀 없음. 앞(510번 슬렌더맨)과 뒤(512번 부활절 장식)는 완전한 개체라 511만 고립된 한 줄. "키사라기역"은 일본 도시전설(사라진 역) 레퍼런스로 보이며 510번(도시전설 테마)과 511 앞뒤 문맥상 관련 있을 수 있으나 확정 못함. 이름만 채우고 나머지 필드는 null로 둠 — 등록 대상 포함 여부는 뽀가 판단 필요(임의로 제외하지 않음).',
});

issues.push({
  ctx: 'char_number=460',
  field: 'poison',
  note: '헤더 괄호 안 표기가 "무독성"(독 없음을 명시) — 표준 6독 아니지만 원문 의도가 명확해서 그대로 poison="무독성"으로 보존함.',
});

const numRange = parsed.map(p => parseInt(p.char_number, 10));
const min = Math.min(...numRange), max = Math.max(...numRange);
const missing = [];
for (let i = min; i <= max; i++) if (!numRange.includes(i)) missing.push(i);

const seen = new Set();
const duplicates = [];
for (const p of parsed) {
  if (seen.has(p.char_number)) duplicates.push(p.char_number);
  seen.add(p.char_number);
}

const starEntities = parsed.filter(p => p.star).map(p => p.char_number);
const offsiteDesignerCount = parsed.filter(p => !p.designer_is_site_user).length;
const defaultDesignerCount = parsed.filter(p => p.designer_is_site_user).length;

const report = {
  summary: {
    total: parsed.length,
    numRange: `${String(min).padStart(3,'0')} ~ ${String(max).padStart(3,'0')}`,
    duplicates,
    missing,
    placeholderSlots: [],
    starEntities,
    daDesignerApplied,
    offsiteDesignerCount,
    defaultDesignerCount,
    errors: [],
    resolvedByPo: [],
  },
  issues,
};

fs.writeFileSync(path.join(__dirname, '..', 'jellfirella_gen3_parsed.json'), JSON.stringify(parsed, null, 2) + '\n', 'utf-8');
fs.writeFileSync(path.join(__dirname, '..', 'jellfirella_gen3_validation_report.json'), JSON.stringify(report, null, 2) + '\n', 'utf-8');

console.log('총 개체수:', parsed.length);
console.log('결번:', missing);
console.log('중복:', duplicates);
console.log('star 개체:', starEntities);
console.log('DA 디자이너:', JSON.stringify(daDesignerApplied));
console.log('issues 개수:', issues.length);
