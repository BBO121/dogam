// 체크포인트 조립 스크립트: tmp_0401_0500/*.txt 파일들을 모아 tails_0401_0500.json 생성
const fs = require('fs');
const path = require('path');

const batchPath = path.join(__dirname, 'batches', 'batch_0401_0500.json');
const tmpDir = path.join(__dirname, 'tmp_0401_0500');
const outPath = path.join(__dirname, 'tails_0401_0500.json');

const batch = JSON.parse(fs.readFileSync(batchPath, 'utf8'));

const result = [];
const missing = [];

batch.forEach((item) => {
  const txtPath = path.join(tmpDir, `${item.number}.txt`);
  if (fs.existsSync(txtPath)) {
    const text = fs.readFileSync(txtPath, 'utf8');
    result.push({ number: item.number, url: item.url, text });
  } else {
    missing.push(item.number);
  }
});

fs.writeFileSync(outPath, JSON.stringify(result, null, 2), 'utf8');
console.log('저장된 항목 수:', result.length);
console.log('아직 누락된 번호:', missing.join(', '));
