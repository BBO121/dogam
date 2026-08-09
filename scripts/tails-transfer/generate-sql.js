#!/usr/bin/env node
'use strict';

// 테일스 개체 소유권 일괄 이전 — 2단계: SQL 생성
//
// 이 스크립트는 DB에 전혀 연결하지 않는다. validate.js가 만든 검증 결과
// JSON 파일만 읽어서, "이전 가능"으로 판정된 건에 대해서만 UPDATE/INSERT
// SQL을 텍스트로 생성한다. 생성된 .sql 파일은 자동 실행되지 않으며,
// Supabase SQL Editor에서 사람이 직접 검토 후 실행해야 한다.
//
// 사용법:
//   node scripts/tails-transfer/generate-sql.js <validate.js 결과 JSON 파일>

const fs = require('fs');
const path = require('path');

const reportPath = process.argv[2];
if (!reportPath) {
  console.error('사용법: node scripts/tails-transfer/generate-sql.js <validation_*.json>');
  process.exit(1);
}

function esc(v) {
  if (v === null || v === undefined) return 'NULL';
  return `'${String(v).replace(/'/g, "''")}'`;
}

const results = JSON.parse(fs.readFileSync(path.resolve(reportPath), 'utf8'));
const targets = results.filter(r => r.판정 === '이전 가능');

if (targets.length === 0) {
  console.error('[중단] "이전 가능"으로 판정된 항목이 없습니다. 검증 결과 파일을 확인하세요.');
  process.exit(1);
}

// DB_char_id가 정수가 아닌 값이 섞여 있으면 즉시 중단 (방어적 검증)
const invalid = targets.filter(r => !Number.isInteger(r.DB_char_id));
if (invalid.length > 0) {
  console.error('[중단] DB_char_id가 올바르지 않은 항목이 있습니다:', invalid);
  process.exit(1);
}

const lines = [];
lines.push('-- ============================================================');
lines.push('-- 테일스 개체 소유권 일괄 연결 SQL (뽀가 직접 입력한 목록 기준)');
lines.push(`-- 생성 시각: ${new Date().toISOString()}`);
lines.push(`-- 검증 결과 파일: ${path.basename(reportPath)}`);
lines.push(`-- 대상 건수: ${targets.length}건`);
lines.push('-- ');
lines.push('-- 이 파일은 자동 실행되지 않습니다.');
lines.push('-- Supabase SQL Editor에서 내용을 검토한 뒤 직접 실행하세요.');
lines.push('-- 문제가 발견되면 COMMIT 이전에 ROLLBACK 하세요.');
lines.push('-- ============================================================');
lines.push('');
lines.push('BEGIN;');
lines.push('');

targets.forEach(r => {
  lines.push(`-- [입력] ${r.입력유저} / ${r.입력개체번호}  →  [DB] #${r.DB_char_number} ${r.DB_name} (id=${r.DB_char_id}) → ${r.매칭계정_nickname}(${r.변경될_owner_user_id})`);
  // owner_nickname은 검증 시점 스냅샷을 신뢰하지 않고, 실행 시점에 auth.users를 직접 조회해 채운다.
  lines.push(
    'UPDATE characters SET\n' +
    `  owner_user_id    = ${esc(r.변경될_owner_user_id)},\n` +
    '  owner_nickname   = (SELECT COALESCE(raw_user_meta_data->>\'display_name\', raw_user_meta_data->>\'nickname\')\n' +
    `                        FROM auth.users WHERE id = ${esc(r.변경될_owner_user_id)}),\n` +
    '  owner_is_offsite = false,\n' +
    '  owner_contact    = NULL,\n' +
    '  folder_id        = NULL,\n' +
    '  pending_transfer = NULL\n' +
    `WHERE id = ${r.DB_char_id}\n` +
    `  AND char_number = ${esc(r.DB_char_number)}\n` +
    "  AND species_name = '테일스'\n" +
    '  AND owner_user_id IS NULL\n' +
    '  AND owner_is_offsite = true;'
  );
  // from_nickname은 검증 시점 스냅샷(참고용 이력 라벨) — 위 UPDATE 실행 전 값이다.
  lines.push(
    'INSERT INTO character_transfers\n' +
    '  (character_id, character_name, species_name, from_user_id, from_nickname, to_user_id, to_nickname, method)\n' +
    'SELECT id, name, \'테일스\', NULL, ' + esc(r.현재_owner_nickname) + ',\n' +
    `       ${esc(r.변경될_owner_user_id)},\n` +
    `       (SELECT COALESCE(raw_user_meta_data->>'display_name', raw_user_meta_data->>'nickname') FROM auth.users WHERE id = ${esc(r.변경될_owner_user_id)}),\n` +
    '       \'일괄 소유권 연결\'\n' +
    `FROM characters WHERE id = ${r.DB_char_id};`
  );
  lines.push('');
});

lines.push('COMMIT;');
lines.push('');
lines.push('-- ▼ 실행 후 검증용 SELECT (위 COMMIT까지 실행한 뒤 별도로 실행)');
lines.push('-- SELECT id, char_number, name, owner_user_id, owner_nickname, owner_is_offsite, owner_contact, folder_id');
lines.push('--   FROM characters');
lines.push(`--  WHERE id IN (${targets.map(r => r.DB_char_id).join(', ')});`);
lines.push('-- 기대 결과: 모든 행의 owner_user_id / owner_nickname이 위 목록과 일치하고,');
lines.push('--            owner_is_offsite = false, owner_contact/folder_id = NULL 이어야 함.');

const outDir = path.resolve(__dirname, 'output');
fs.mkdirSync(outDir, { recursive: true });
const ts = new Date().toISOString().replace(/[:.]/g, '-');
const outPath = path.join(outDir, `transfer_${ts}.sql`);
fs.writeFileSync(outPath, lines.join('\n'), 'utf8');

console.log(`SQL 생성 완료: ${targets.length}건`);
console.log(`파일: ${outPath}`);
console.log('내용을 직접 검토한 뒤 Supabase SQL Editor에서 실행하세요.');
