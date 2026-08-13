const fs = require('fs');
const path = require('path');

const { mapping, orphaned } = JSON.parse(fs.readFileSync(path.join(__dirname, 'mapping_gen3.json'), 'utf-8'));

// 아기+성체 이중 문단이 확인된 개체 (원문에 이미지 2장: 아기 먼저, 성체 나중)
const dualImageEntries = new Set(['469','478','526','529','531','538','539','540','541','543','544','581','584']);
// 401은 문서 맨 앞이라 종족 소개 배너 이미지가 섞여있던 케이스(gen2 201번과 동일 패턴) - 마지막 것만 실사용
const bannerCase = new Set(['401']);

const srcDir = __dirname;
const destDir = path.join(__dirname, '..', 'images');

const copied = [];
const copiedAlt = [];
const noImage = [];
const stillOrphaned = {};

for (const num of Object.keys(mapping).sort((a,b)=>+a-+b)) {
  const primary = mapping[num];
  const orphanList = orphaned[num] || [];

  if (!primary) { noImage.push(num); continue; }

  if (dualImageEntries.has(num) && orphanList.length === 1) {
    // 첫 장(아기)=orphanList[0] -> 대표, 둘째 장(성체)=primary -> alt
    fs.copyFileSync(path.join(srcDir, orphanList[0]), path.join(destDir, `jellfi_${num}.png`));
    fs.copyFileSync(path.join(srcDir, primary), path.join(destDir, `jellfi_${num}_alt.png`));
    copied.push({ char_number: num, src: orphanList[0], note: '아기 이미지(대표)' });
    copiedAlt.push({ char_number: num, src: primary, note: '성체 이미지(_alt)' });
  } else if (bannerCase.has(num)) {
    fs.copyFileSync(path.join(srcDir, primary), path.join(destDir, `jellfi_${num}.png`));
    copied.push({ char_number: num, src: primary });
    if (orphanList.length) stillOrphaned[num] = orphanList; // 배너로 간주, 버림
  } else {
    fs.copyFileSync(path.join(srcDir, primary), path.join(destDir, `jellfi_${num}.png`));
    copied.push({ char_number: num, src: primary });
    if (orphanList.length) stillOrphaned[num] = orphanList; // 예상 밖 다중이미지, 별도 표시
  }
}

console.log('대표 이미지 복사됨:', copied.length);
console.log('_alt 이미지 복사됨:', copiedAlt.length);
console.log('이미지 없음:', noImage);
console.log('여전히 orphaned(미확인 다중이미지):', stillOrphaned);

fs.writeFileSync(
  path.join(__dirname, '..', 'image_extract_report_gen3.json'),
  JSON.stringify({
    convention: '이미지는 뒤따르는 [번호] 마커에 귀속 (이미지 먼저, 캡션 나중). 아기+성체 이중 이미지 개체는 첫 장을 대표, 둘째 장을 _alt로 보관.',
    copied,
    copiedAlt,
    noImage,
    dualImageEntries: [...dualImageEntries],
    bannerDiscarded: { '401': orphaned['401'] || [] },
    stillOrphaned,
  }, null, 2),
  'utf-8'
);
