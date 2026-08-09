#!/usr/bin/env node
'use strict';

// 테일스 개체 소유권 일괄 이전 — 1단계: 검증 (읽기 전용)
//
// 이 스크립트는 characters / get_all_users_full() 을 SELECT로만 조회한다.
// DB에 UPDATE/INSERT/DELETE를 실행하는 코드는 절대 포함하지 않는다.
// 실제 소유권 변경은 이 결과를 사람이 검토한 뒤 generate-sql.js로 SQL을
// 만들고, Supabase SQL Editor에서 직접 실행해야 한다.
//
// 사용법:
//   node scripts/tails-transfer/validate.js <입력파일.txt>
//
// 입력파일 형식 (줄 단위):
//   닉네임또는아이디 / 101, 205, 333
//   ms1sharklee / 510, 511

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('[오류] .env에 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY가 설정되어 있지 않습니다.');
  console.error('       .env.example을 복사해 .env를 만들고 값을 채워주세요.');
  process.exit(1);
}

const inputPath = process.argv[2];
if (!inputPath) {
  console.error('사용법: node scripts/tails-transfer/validate.js <입력파일.txt>');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// "0101" / "101" / "1" 을 모두 같은 개체번호로 취급하기 위해 앞자리 0을 제거해 정규화한다.
function normalizeNumber(raw) {
  const digits = String(raw).trim().replace(/[^\d]/g, '');
  if (!digits) return null;
  return digits.replace(/^0+(?=\d)/, '');
}

// "닉네임 / 101, 205, 333" 줄들을 (user, charNumberRaw) 쌍으로 펼친다.
function parseInput(text) {
  const rows = [];
  const errors = [];
  text.split(/\r?\n/).forEach((line, idx) => {
    const trimmed = line.trim();
    if (!trimmed) return;

    const sepIdx = trimmed.indexOf('/');
    if (sepIdx === -1) {
      errors.push({ 줄번호: idx + 1, 원본: trimmed, 사유: "구분자 '/'를 찾을 수 없음" });
      return;
    }

    const user = trimmed.slice(0, sepIdx).trim();
    const numsPart = trimmed.slice(sepIdx + 1).trim();
    const nums = numsPart.split(',').map(s => s.trim()).filter(Boolean);

    if (!user || nums.length === 0) {
      errors.push({ 줄번호: idx + 1, 원본: trimmed, 사유: '유저 또는 개체번호가 비어있음' });
      return;
    }
    nums.forEach(n => rows.push({ user, charNumberRaw: n, lineNo: idx + 1 }));
  });
  return { rows, errors };
}

async function main() {
  const text = fs.readFileSync(path.resolve(inputPath), 'utf8');
  const { rows, errors: parseErrors } = parseInput(text);

  // 같은 (유저, 개체번호) 조합이 여러 줄에 걸쳐 중복 입력돼도 한 건으로 처리
  const seen = new Set();
  const pairs = [];
  rows.forEach(r => {
    const key = `${r.user}::${normalizeNumber(r.charNumberRaw)}`;
    if (seen.has(key)) return;
    seen.add(key);
    pairs.push(r);
  });

  console.log(`입력 파싱: 유효 ${pairs.length}건 (중복 제거 후), 형식 오류 ${parseErrors.length}건`);

  const { data: users, error: userErr } = await sb.rpc('get_all_users_full');
  if (userErr) {
    console.error('[오류] 유저 목록 조회 실패:', userErr.message);
    process.exit(1);
  }

  // 대상 종족은 반드시 '테일스'로 고정 — 다른 종족은 절대 조회 대상에 포함하지 않는다.
  // Supabase 기본 1000행 제한을 넘는 경우를 대비해 페이지네이션한다 (species.html의 동일 버그 수정과 같은 방식).
  const chars = [];
  {
    const pageSize = 1000;
    let from = 0;
    while (true) {
      const { data: page, error: charErr } = await sb
        .from('characters')
        .select('id, char_number, name, species_name, owner_user_id, owner_nickname, owner_is_offsite')
        .eq('species_name', '테일스')
        .range(from, from + pageSize - 1);
      if (charErr) {
        console.error('[오류] 테일스 개체 목록 조회 실패:', charErr.message);
        process.exit(1);
      }
      if (!page || !page.length) break;
      chars.push(...page);
      if (page.length < pageSize) break;
      from += pageSize;
    }
  }

  // 유저 식별값 → 계정 매칭 (닉네임 또는 로그인ID 완전 일치, 대소문자 무시)
  // 주의: characters.owner_nickname / owner_contact는 절대 이 매칭에 사용하지 않는다.
  function findUsers(identifier) {
    const idLower = identifier.trim().toLowerCase();
    const matchedIds = new Set(
      users
        .filter(u =>
          (u.nickname && u.nickname.toLowerCase() === idLower) ||
          (u.login_id && u.login_id.toLowerCase() === idLower)
        )
        .map(u => u.id)
    );
    return [...matchedIds].map(id => users.find(u => u.id === id));
  }

  const charsByNorm = new Map();
  chars.forEach(c => {
    const norm = normalizeNumber(c.char_number);
    if (!charsByNorm.has(norm)) charsByNorm.set(norm, []);
    charsByNorm.get(norm).push(c);
  });

  // 입력 목록 안에서 같은 개체번호가 서로 다른 유저에게 지정된 경우 — 의도가 불명확하므로 전부 확인 필요 처리
  const charNumberToUsers = new Map();
  pairs.forEach(p => {
    const norm = normalizeNumber(p.charNumberRaw);
    if (!charNumberToUsers.has(norm)) charNumberToUsers.set(norm, new Set());
    charNumberToUsers.get(norm).add(p.user);
  });
  const conflictingNumbers = new Set(
    [...charNumberToUsers.entries()].filter(([, us]) => us.size > 1).map(([n]) => n)
  );

  const results = [];

  for (const p of pairs) {
    const norm = normalizeNumber(p.charNumberRaw);
    const base = { 입력유저: p.user, 입력개체번호: p.charNumberRaw };

    if (norm === null) {
      results.push({ ...base, 판정: '확인 필요', 사유: '개체번호에서 숫자를 추출할 수 없음' });
      continue;
    }

    if (conflictingNumbers.has(norm)) {
      results.push({ ...base, 판정: '확인 필요', 사유: `입력 목록 내 개체번호(${p.charNumberRaw})가 서로 다른 유저에게 중복 지정됨` });
      continue;
    }

    const matchedUsers = findUsers(p.user);
    if (matchedUsers.length === 0) {
      results.push({ ...base, 판정: '확인 필요', 사유: '유저를 찾지 못함 (해당 닉네임/아이디의 사이트 계정 없음)' });
      continue;
    }
    if (matchedUsers.length > 1) {
      results.push({
        ...base,
        판정: '확인 필요',
        사유: `동일 식별값으로 유저 후보 ${matchedUsers.length}건 발견`,
        후보목록: matchedUsers.map(u => ({ user_id: u.id, nickname: u.nickname, login_id: u.login_id })),
      });
      continue;
    }
    const targetUser = matchedUsers[0];

    const matchedChars = charsByNorm.get(norm) || [];
    if (matchedChars.length === 0) {
      results.push({
        ...base,
        매칭계정_user_id: targetUser.id,
        매칭계정_nickname: targetUser.nickname,
        판정: '확인 필요',
        사유: '테일스 중 해당 개체번호를 찾지 못함',
      });
      continue;
    }
    if (matchedChars.length > 1) {
      results.push({
        ...base,
        매칭계정_user_id: targetUser.id,
        매칭계정_nickname: targetUser.nickname,
        판정: '확인 필요',
        사유: `동일 개체번호가 테일스 내에서 중복됨 (${matchedChars.length}건)`,
        DB_id목록: matchedChars.map(c => c.id),
      });
      continue;
    }

    const c = matchedChars[0];
    const row = {
      ...base,
      매칭계정_user_id: targetUser.id,
      매칭계정_nickname: targetUser.nickname,
      매칭계정_login_id: targetUser.login_id,
      DB_char_id: c.id,
      DB_char_number: c.char_number,
      DB_name: c.name,
      현재_owner_user_id: c.owner_user_id,
      현재_owner_nickname: c.owner_nickname,
    };

    if (c.owner_user_id) {
      const same = c.owner_user_id === targetUser.id;
      results.push({
        ...row,
        판정: '확인 필요',
        사유: same
          ? '이미 해당 유저 소유로 설정되어 있음 (변경 불필요)'
          : '이미 다른 종족연구소 가입 유저가 소유자로 설정되어 있음',
      });
      continue;
    }

    if (c.owner_is_offsite !== true) {
      results.push({
        ...row,
        판정: '확인 필요',
        사유: '오프사이트 소유 개체가 아님 (owner_is_offsite=false) — 자동 처리 대상에서 제외, 수동 확인 필요',
      });
      continue;
    }

    results.push({
      ...row,
      변경될_owner_user_id: targetUser.id,
      변경될_owner_nickname: targetUser.nickname,
      판정: '이전 가능',
      사유: '',
    });
  }

  parseErrors.forEach(e => {
    results.push({ 입력유저: null, 입력raw: e.원본, 줄번호: e.줄번호, 판정: '확인 필요', 사유: `입력 형식 오류: ${e.사유}` });
  });

  const okCount = results.filter(r => r.판정 === '이전 가능').length;
  const needCheckCount = results.length - okCount;

  console.log(`\n검증 결과: 이전 가능 ${okCount}건 / 확인 필요 ${needCheckCount}건\n`);
  console.table(results.map(r => ({
    입력유저: r.입력유저 ?? '-',
    입력번호: r.입력개체번호 ?? r.입력raw ?? '-',
    매칭계정: r.매칭계정_nickname ?? '-',
    DB번호: r.DB_char_number ?? '-',
    DB이름: r.DB_name ?? '-',
    현재소유자: r.현재_owner_nickname ?? '-',
    판정: r.판정,
    사유: r.사유 || '-',
  })));

  const outDir = path.resolve(__dirname, 'output');
  fs.mkdirSync(outDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const outPath = path.join(outDir, `validation_${ts}.json`);
  fs.writeFileSync(outPath, JSON.stringify(results, null, 2), 'utf8');

  console.log(`\n결과 파일 저장됨: ${outPath}`);
  console.log('이 파일을 직접 확인한 뒤에만 generate-sql.js로 SQL을 생성하세요.');
}

main().catch(e => {
  console.error('[예외 발생]', e);
  process.exit(1);
});
