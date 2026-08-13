const fs = require('fs');
const path = require('path');

const mappingList = JSON.parse(fs.readFileSync(path.join(__dirname, 'mapping_gen4_list.json'), 'utf-8'));
const diag = JSON.parse(fs.readFileSync(path.join(__dirname, 'parse_diagnostics.json'), 'utf-8'));
const notRegistrable = new Set([...diag.emptySlots, ...diag.stubNames]);

const srcDir = __dirname;
const destDir = path.join(__dirname, '..', 'images');

// 762는 중복 마커라 이미지도 2장(서로 다른 개체) — 자동 복사하지 않고 별도 보관, 뽀 결정 대기
const dup762 = mappingList.filter(x => x.num === '762');

const copied = [];
const noImage = [];
const skippedNotRegistrable = [];

for (const entry of mappingList) {
  const num = entry.num;
  if (num === '762') continue; // 아래서 별도 처리
  if (notRegistrable.has(num)) { skippedNotRegistrable.push(num); continue; }
  if (!entry.img) { noImage.push(num); continue; }
  fs.copyFileSync(path.join(srcDir, entry.img), path.join(destDir, `jellfi_${num}.png`));
  copied.push({ char_number: num, src: entry.img });
}

// 762 이미지 둘 다 임시 보관(등록에는 미사용, 뽀 결정 후 처리)
dup762.forEach((entry, i) => {
  if (entry.img) {
    const tmpName = `jellfi_762_candidate${i + 1}.png`;
    fs.copyFileSync(path.join(srcDir, entry.img), path.join(destDir, tmpName));
  }
});

console.log('복사됨(실제 등록대상):', copied.length);
console.log('등록대상 아님(빈슬롯/스텁)이라 건너뜀:', skippedNotRegistrable.length);
console.log('실제 개체인데 이미지 없음:', noImage);
console.log('762 후보 이미지:', dup762.map((e, i) => `candidate${i+1}: ${e.img}`));

fs.writeFileSync(
  path.join(__dirname, '..', 'image_extract_report_gen4.json'),
  JSON.stringify({
    convention: '이미지는 뒤따르는 [번호] 마커에 귀속',
    copied, noImage, skippedNotRegistrable,
    dup762Candidates: dup762.map((e, i) => ({ candidate: i + 1, src: e.img, savedAs: e.img ? `jellfi_762_candidate${i+1}.png` : null }))
  }, null, 2),
  'utf-8'
);
