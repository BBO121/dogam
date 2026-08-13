const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '_Jellfirella_2_2_.html'), 'utf-8');

const numRe = /\[(\d{3})\]/g;
const imgRe = /<img[^>]+src="(images\/image\d+\.png)"/g;
const events = [];
let m;
while ((m = numRe.exec(html))) events.push({ pos: m.index, type: 'num', value: m[1] });
while ((m = imgRe.exec(html))) events.push({ pos: m.index, type: 'img', value: m[1] });
events.sort((a, b) => a.pos - b.pos);

// 검증된 규칙: 이미지는 뒤따르는 [번호] 마커에 귀속. 한 마커 앞에 여러 장이 뭉치면 마지막(가장 가까운) 것만 채택.
const mapping = {};
const orphaned = {};
let pending = [];
for (const ev of events) {
  if (ev.type === 'img') pending.push(ev.value);
  else {
    if (pending.length > 0) {
      mapping[ev.value] = pending[pending.length - 1];
      if (pending.length > 1) orphaned[ev.value] = pending.slice(0, -1);
    } else {
      mapping[ev.value] = null;
    }
    pending = [];
  }
}
const trailingAfterLast = pending;

const parsed = require(path.join(__dirname, '..', 'jellfirella_gen3_parsed.json'));
const realNums = new Set(parsed.map(p => p.char_number));

const zero = Object.keys(mapping).filter(n => !mapping[n]);
const realZero = zero.filter(n => realNums.has(n));

console.log('마커 총 개수:', Object.keys(mapping).length);
console.log('trailing (마지막 마커 뒤 이미지, 보통 종족 마무리 배너):', trailingAfterLast);
console.log('전체 zero:', zero.length, zero);
console.log('실제 등록대상인데 이미지 없는 번호:', realZero);
console.log('orphaned:', orphaned);

fs.writeFileSync(path.join(__dirname, 'mapping_gen3.json'), JSON.stringify({ mapping, orphaned }, null, 2), 'utf-8');
