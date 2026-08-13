const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const txt = fs.readFileSync(path.join(ROOT, 'jellfirella_raw_gen4.txt'), 'utf-8');

const posRe = /(\*{0,2})\[(\d{3})\]/g;
let m; const markers = [];
while ((m = posRe.exec(txt))) markers.push({ star: m[1].length > 0, num: m[2], idx: m.index, endIdx: m.index + m[0].length });

const entries = markers.map((mk, i) => {
  const next = markers[i + 1];
  const end = next ? next.idx : txt.length;
  return { star: mk.star, num: mk.num, raw: txt.slice(mk.endIdx, end) };
});

const DEFAULT_DESIGNER = { designer_nickname: '새', designer_user_id: '4eebcb25-f03b-4d8e-a020-6fc2f16cfacc', designer_is_site_user: true };

function parseHeader(firstLine) {
  // "이름 (독) - '오너' 님의 ..." 또는 변형들
  const q = `['‘’]`;
  const re = new RegExp(`^(.*?)(?:\\s*\\(([^)]*)\\))?\\s*-\\s*${q}([^'‘’]*)${q}`, 'u');
  const mm = firstLine.match(re);
  if (mm) {
    return { name: mm[1].trim(), poison: mm[2] ? mm[2].trim() : null, owner: mm[3].trim() };
  }
  // 괄호만 있고 소유주 따옴표 없는 경우
  const re2 = firstLine.match(/^(.*?)\s*\(([^)]*)\)\s*$/);
  if (re2) return { name: re2[1].trim(), poison: re2[2].trim(), owner: null, noOwnerClause: true };
  return null;
}

const parsed = [];
const issues = [];
const emptySlots = [];
const stubNames = [];
const daApplied = [];
const dualMarkerNums = new Set();

const seen = new Set();
for (const e of entries) {
  if (seen.has(e.num)) dualMarkerNums.add(e.num);
  seen.add(e.num);
}

for (const e of entries) {
  const body = e.raw.replace(/\r\n/g, '\n');
  const trimmed = body.trim();

  const base = {
    char_number: e.num,
    star: e.star,
    name: null,
    poison: null,
    owner_nickname: null,
    ...(e.star ? { designer_nickname: null, designer_user_id: null, designer_is_site_user: false } : { ...DEFAULT_DESIGNER }),
    classification: '특수개체',
    description: null,
    image_local_path: `register/jellfirella/images/jellfi_${e.num}.png`,
    _dupMarker: dualMarkerNums.has(e.num),
  };

  if (!trimmed) {
    emptySlots.push(e.num);
    parsed.push(base);
    continue;
  }

  const lines = trimmed.split(/\n+/).map(l => l.trim()).filter(Boolean);
  const firstLine = lines[0];
  const rest = lines.slice(1).join('\n').trim();

  const h = parseHeader(firstLine);

  if (!h) {
    // 이름만 있는 스텁 (괄호/따옴표 전혀 없음) — gen3 511번 선례대로 소유주는 기본값 '새'
    base.name = firstLine;
    base.owner_nickname = '새';
    if (rest) base.description = rest; // 혹시 이름 뒤에 뭔가 더 있으면 보존
    stubNames.push(e.num);
    parsed.push(base);
    continue;
  }

  base.name = h.name || null;
  base.poison = h.poison || null;
  base.owner_nickname = h.owner || null;
  // 헤더 문장이 줄바꿈으로 끊겨서(예: "‘여늑댐’\r\n 님의 친구가 되었습니다.") 소유주 문구 뒷부분이
  // description 첫 줄로 잘못 들어간 경우 제거 (717번에서 발견)
  let cleanRest = rest;
  const contMatch = cleanRest.match(/^님[^\n]*(?:되었습니다|함께하기를|것이다)\.?\s*\n?/);
  if (contMatch) cleanRest = cleanRest.slice(contMatch[0].length).trim();
  base.description = cleanRest || null;

  if (h.noOwnerClause) {
    issues.push({ ctx: `char_number=${e.num}`, field: 'owner', note: `소유주 문구('...' 님) 자체가 헤더에 없음. 헤더 원문: "${firstLine}"` });
  }
  if (!base.owner_nickname) base.owner_nickname = '새';

  // 예외A (star): 소유주=디자이너
  if (e.star) {
    base.designer_nickname = base.owner_nickname;
    base.designer_user_id = null;
    base.designer_is_site_user = false;
  }

  // DA/D 디자이너 크레딧 규칙 — 헤더+description 전체에서 검색
  // 1) "~님 DA" / "~님 D" (가장 흔한 패턴, 님 앞 토큰을 lazy하게 캡처해서 '님' 자체가 이름에 섞여 들어가지 않게 함)
  // 2) 님 없이 바로 붙는 변형 "이름DA" (gen1 041/042 "로문DA" 선례)
  const fullText = firstLine + '\n' + rest;
  let daMatch = fullText.match(/(\S+?)님\s*DA?(?![가-힣A-Za-z])/);
  let daRaw = daMatch ? daMatch[0].trim() : null;
  let designer = daMatch ? daMatch[1] : null;
  if (!daMatch) {
    const alt = fullText.match(/(\S+?)DA(?![가-힣A-Za-z])/);
    if (alt) { daMatch = alt; designer = alt[1]; daRaw = alt[0].trim(); }
  }
  if (daMatch) {
    base.designer_nickname = designer;
    base.designer_user_id = null;
    base.designer_is_site_user = false;
    daApplied.push({ char_number: e.num, designer, raw: daRaw });
  }

  parsed.push(base);
}

// 진짜 결번 계산
const nums = [...new Set(entries.map(e => parseInt(e.num, 10)))].sort((a, b) => a - b);
const missing = [];
for (let i = nums[0]; i <= nums[nums.length - 1]; i++) if (!nums.includes(i)) missing.push(i);

fs.writeFileSync(path.join(ROOT, 'jellfirella_gen4_parsed.json'), JSON.stringify(parsed, null, 2) + '\n', 'utf-8');

console.log('총 마커:', entries.length, '고유번호:', nums.length);
console.log('range:', nums[0], '~', nums[nums.length - 1]);
console.log('진짜 결번:', missing.length, JSON.stringify(missing));
console.log('빈 슬롯(내용 전혀 없음):', emptySlots.length, JSON.stringify(emptySlots));
console.log('이름만 있는 스텁:', stubNames.length, JSON.stringify(stubNames));
console.log('DA/D 재지정:', JSON.stringify(daApplied, null, 2));
console.log('중복 마커 번호:', [...dualMarkerNums]);
console.log('parse 이슈(noOwnerClause 등):', JSON.stringify(issues, null, 2));

fs.writeFileSync(path.join(__dirname, 'parse_diagnostics.json'), JSON.stringify({
  missing, emptySlots, stubNames, daApplied, dualMarkerNums: [...dualMarkerNums], issues
}, null, 2));
