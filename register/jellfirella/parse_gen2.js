// 젤피렐라 2세대(201~400) 파싱 스크립트
// 실행: node parse_gen2.js
const fs = require('fs');
const path = require('path');

const RAW_PATH = path.join(__dirname, 'jellfirella_raw_gen2.txt');
const OUT_PARSED = path.join(__dirname, 'jellfirella_gen2_parsed.json');
const OUT_REPORT = path.join(__dirname, 'jellfirella_gen2_validation_report.json');

const DEFAULT_DESIGNER_NICK = '새';
const DEFAULT_DESIGNER_ID = '4eebcb25-f03b-4d8e-a020-6fc2f16cfacc';

const raw = fs.readFileSync(RAW_PATH, 'utf-8');

// 개체 블록 분리: 줄 시작이 [숫자] 또는 *[숫자] 인 지점을 마커로 찾고, 마커 사이 구간을 슬라이스
// (CRLF 환경에서 lookahead에 '$'를 섞으면 매 빈 줄마다 조기 매치되는 버그가 있어 슬라이스 방식으로 처리)
const markerRe = /^(\*?)\[(\d{3})\]([^\r\n]*)/gm;
const markers = [];
let mk;
while ((mk = markerRe.exec(raw))) {
  markers.push({
    star: mk[1] === '*',
    char_number: mk[2],
    headerRest: mk[3].trim(),
    start: mk.index,
    headerEnd: mk.index + mk[0].length,
  });
}

const entries = markers.map((cur, i) => {
  const next = markers[i + 1];
  const bodyRaw = raw.slice(cur.headerEnd, next ? next.start : raw.length);
  return { char_number: cur.char_number, star: cur.star, headerRest: cur.headerRest, body: bodyRaw.trim() };
});

const issues = [];
const daDesigners = []; // { char_number, designer }
const placeholders = []; // 미확정 슬롯

function extractDesignerFromText(text) {
  // "OO님 DA" / "OO님 D" (단독) / "OO OO2DA" 붙어있는 변형
  let mm = text.match(/([^\s,.:‘’'"]+)\s*님\s*DA/);
  if (mm) return mm[1];
  mm = text.match(/([^\s,.:‘’'"]+)\s*님\s*D(?!A)\b/);
  if (mm) return mm[1];
  // "블래키 로문DA" 처럼 공백으로 구분되고 DA가 바로 붙는 경우: DA 직전 이름 토큰
  mm = text.match(/([^\s]+)DA/);
  if (mm) return mm[1];
  return null;
}

const results = [];

for (const { char_number, star, headerRest, body } of entries) {
  // 플레이스홀더 슬롯: "OO님 디자인권" 또는 "이벤트 디자인권"
  const placeholderMatch = headerRest.match(/^(.*?)디자인권\s*$/);
  if (placeholderMatch && !headerRest.includes('(')) {
    const who = placeholderMatch[1].replace(/님\s*$/, '').trim();
    placeholders.push({ char_number, star, who: who || null });
    results.push({
      char_number,
      star,
      name: null,
      poison: null,
      owner_nickname: who || null,
      designer_nickname: star ? (who || null) : DEFAULT_DESIGNER_NICK,
      designer_user_id: star ? null : DEFAULT_DESIGNER_ID,
      designer_is_site_user: star ? false : true,
      classification: '특수개체',
      description: null,
      image_local_path: `register/jellfirella/images/jellfi_${char_number}.png`,
      _placeholder: true,
    });
    continue;
  }

  // 헤더: "이름 (독) - '소유주' 님의 ~" 형태
  // 이름/독 분리
  const parenMatch = headerRest.match(/^(.*?)\s*\(([^)]*)\)\s*(.*)$/);
  let name, poison, afterParen;
  if (parenMatch) {
    name = parenMatch[1].trim();
    poison = parenMatch[2].trim();
    afterParen = parenMatch[3].trim();
  } else {
    // 296, 380처럼 괄호(독) 표기가 없는 경우
    const dashIdx = headerRest.indexOf(' - ');
    if (dashIdx >= 0) {
      name = headerRest.slice(0, dashIdx).trim();
      afterParen = headerRest.slice(dashIdx + 3).trim();
    } else {
      name = headerRest.trim();
      afterParen = '';
    }
    poison = null;
    issues.push({ ctx: `char_number=${char_number}`, field: 'poison', note: `헤더에 (독) 표기 없음. 원문: "${headerRest}"` });
  }

  // 소유주: '...' 님 패턴
  let owner_nickname = null;
  const ownerMatch = afterParen.match(/[‘']([^’']+)[’']\s*님/);
  if (ownerMatch) {
    owner_nickname = ownerMatch[1].trim();
  } else if (afterParen) {
    issues.push({ ctx: `char_number=${char_number}`, field: 'owner', note: `소유주('...' 님) 패턴을 헤더에서 찾을 수 없음. 원문: "${headerRest}"` });
  } else {
    issues.push({ ctx: `char_number=${char_number}`, field: 'owner', note: `헤더에 소유주 언급 자체가 없음(뒤 문구 없음). 원문: "${headerRest}"` });
  }

  // 296: 헤더엔 독 표기 없지만 본문에 실제 독 이름이 언급되는 경우 참고용으로 캡처
  if (poison === null && body) {
    const bodyPoisonMatch = body.match(/(전기독|화염독|물결독|식물독|섬광독|암흑독)/);
    if (bodyPoisonMatch) {
      issues.push({ ctx: `char_number=${char_number}`, field: 'poison', note: `헤더엔 독 표기 없으나 본문에 "${bodyPoisonMatch[1]}" 언급됨 — 뽀 확인 필요(자동 반영 안 함, poison=null로 둠)` });
    }
  }

  // description: body 전체에서 DA/D 태그 라인 제거
  const bodyLines = body.split(/\r?\n/);
  let designerOverride = null;
  const descLines = [];
  for (const line of bodyLines) {
    const t = line.trim();
    if (!t) continue;
    const d = extractDesignerFromText(t);
    if (d && t.length < 40) {
      // 짧은 태그성 줄(디자이너 표기 전용 줄)로 판단, description에서 제외
      designerOverride = d;
      daDesigners.push({ char_number, designer: d, raw: t });
      continue;
    }
    if (/^디자인\s*도움/.test(t) && t.length < 40) {
      // "디자인 도움: OO님" 태그 줄 — description에서 제외(아래 helpMatch에서 별도 issue로 기록)
      continue;
    }
    descLines.push(t);
  }
  // description 자체 문장 속에 DA가 섞여 있을 수도 있으니 한 번 더 스캔(태그 줄이 아니었던 경우 대비)
  if (!designerOverride) {
    const inlineD = extractDesignerFromText(body);
    if (inlineD) {
      designerOverride = inlineD;
      daDesigners.push({ char_number, designer: inlineD, raw: '(description 내부)' });
    }
  }

  const description = descLines.join(' ').replace(/\s+/g, ' ').trim() || null;

  // "디자인 도움: OO님" -> 참고 issue만, override 아님
  const helpMatch = body.match(/디자인\s*도움\s*[:：]\s*([^\s,.]+)/);
  if (helpMatch) {
    const helpName = helpMatch[1].replace(/님$/, '');
    issues.push({ ctx: `char_number=${char_number}`, field: 'designer', note: `본문에 "디자인 도움: ${helpName}님" 표기 있음 — 주디자이너는 기본값 유지, 보조 디자이너 크레딧으로만 기록. 뽀 확인 필요.` });
  }

  let designer_nickname, designer_user_id, designer_is_site_user;
  if (designerOverride) {
    designer_nickname = designerOverride;
    designer_user_id = null;
    designer_is_site_user = false;
  } else if (star) {
    designer_nickname = owner_nickname;
    designer_user_id = null;
    designer_is_site_user = false;
  } else {
    designer_nickname = DEFAULT_DESIGNER_NICK;
    designer_user_id = DEFAULT_DESIGNER_ID;
    designer_is_site_user = true;
  }

  if (!name) {
    issues.push({ ctx: `char_number=${char_number}`, field: 'name', note: '이름이 비어있음' });
  }

  results.push({
    char_number,
    star,
    name: name || null,
    poison,
    owner_nickname,
    designer_nickname,
    designer_user_id,
    designer_is_site_user,
    classification: '특수개체',
    description,
    image_local_path: `register/jellfirella/images/jellfi_${char_number}.png`,
  });
}

// 검증
const total = results.length;
const nums = results.map(r => parseInt(r.char_number, 10));
const numSet = new Set(nums);
const duplicates = nums.filter((n, i) => nums.indexOf(n) !== i);
const missing = [];
for (let i = 201; i <= 400; i++) if (!numSet.has(i)) missing.push(i);

const starEntities = results.filter(r => r.star).map(r => r.char_number);
const offsiteDesignerCount = results.filter(r => r.designer_is_site_user === false).length;
const defaultDesignerCount = results.filter(r => r.designer_is_site_user === true).length;
const placeholderNums = results.filter(r => r._placeholder).map(r => r.char_number);

const output = results.map(({ _placeholder, ...rest }) => rest);

fs.writeFileSync(OUT_PARSED, JSON.stringify(output, null, 2) + '\n', 'utf-8');

const report = {
  summary: {
    total,
    numRange: '201 ~ 400',
    duplicates,
    missing,
    placeholderSlots: placeholderNums,
    starEntities,
    daDesignerApplied: daDesigners,
    offsiteDesignerCount,
    defaultDesignerCount,
    errors: [],
  },
  issues,
};

fs.writeFileSync(OUT_REPORT, JSON.stringify(report, null, 2) + '\n', 'utf-8');

console.log('total:', total);
console.log('missing:', missing);
console.log('duplicates:', duplicates);
console.log('placeholders:', placeholderNums);
console.log('star count:', starEntities.length);
console.log('DA designer applied:', daDesigners.length);
console.log('offsite designer count:', offsiteDesignerCount);
console.log('issues count:', issues.length);
