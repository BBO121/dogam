const fs = require('fs');
const path = require('path');

const { mapping, orphaned } = JSON.parse(fs.readFileSync(path.join(__dirname, 'mapping_v2.json'), 'utf-8'));
const placeholders = new Set(['267','268','279','281','282','286','287','289','290','318','319','323','393','399']);

const srcDir = __dirname;
const destDir = path.join(__dirname, '..', 'images');

// 기존(잘못된 구버전 매칭으로 복사됐던) 201~400 이미지 전부 제거 후 재생성
for (const f of fs.readdirSync(destDir)) {
  const m = f.match(/^jellfi_(\d{3})(_alt\d*)?\.png$/);
  if (m && +m[1] >= 201 && +m[1] <= 400) fs.unlinkSync(path.join(destDir, f));
}

const copied = [];
const noImage = [];

for (const num of Object.keys(mapping).sort((a,b)=>+a-+b)) {
  if (placeholders.has(num)) continue; // 미확정 예약 슬롯은 등록 대상 아님, 이미지 복사 안 함
  const img = mapping[num];
  if (!img) { noImage.push(num); continue; }
  fs.copyFileSync(path.join(srcDir, img), path.join(destDir, `jellfi_${num}.png`));
  copied.push({ char_number: num, src: img });
}

console.log('복사됨:', copied.length);
console.log('실제 개체인데 이미지 없음:', noImage);

fs.writeFileSync(
  path.join(__dirname, '..', 'image_extract_report_gen2.json'),
  JSON.stringify({ convention: '이미지는 뒤따르는 [번호] 마커에 귀속 (이미지 먼저, 캡션 나중)', copied, noImage, orphanedDiscarded: orphaned, placeholdersSkipped: [...placeholders] }, null, 2),
  'utf-8'
);
