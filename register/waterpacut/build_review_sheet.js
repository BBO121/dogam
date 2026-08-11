const fs = require('fs');
const r = require('./waterpacut_parsed.json');
const real = r.filter(e => e.name && e.name.trim() !== '');

function csvEscape(v) {
  if (v === null || v === undefined) v = '';
  v = String(v);
  if (/[",\n]/.test(v)) {
    v = '"' + v.replace(/"/g, '""') + '"';
  }
  return v;
}

const header = ['개체번호','개체명','소유주','디자이너','분류','개체분류','개체설명','비고(원본 특이사항, 검수참고용)'];
const rows = [header];

for (const e of real) {
  const num = e.num.padStart(3, '0');
  const owner = e.owner || '';
  const remark = e.notes
    .filter(n => n.startsWith('PRE_TAGS'))
    .map(n => n.replace('PRE_TAGS: ', ''))
    .join(' / ');
  rows.push([
    num,
    e.name,
    owner,
    '', // 디자이너
    e.classification || '',
    '', // 개체분류
    e.description,
    remark,
  ]);
}

const csv = rows.map(r => r.map(csvEscape).join(',')).join('\r\n');
fs.writeFileSync('waterpacut_review_sheet.csv', '﻿' + csv, 'utf8'); // BOM for Excel Korean
console.log('rows written (excl header):', rows.length - 1);
