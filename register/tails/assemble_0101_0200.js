const fs = require('fs');
const path = require('path');

const batch = JSON.parse(fs.readFileSync(path.join(__dirname, 'batches', 'batch_0101_0200.json'), 'utf8'));
const rawDir = path.join(__dirname, 'raw_0101_0200');

const result = [];
const missing = [];

for (const item of batch) {
  const rawPath = path.join(rawDir, `${item.number}.txt`);
  if (fs.existsSync(rawPath)) {
    const text = fs.readFileSync(rawPath, 'utf8');
    result.push({ number: item.number, url: item.url, text });
  } else {
    missing.push(item.number);
  }
}

fs.writeFileSync(path.join(__dirname, 'tails_0101_0200.json'), JSON.stringify(result, null, 2), 'utf8');
console.log(`저장 완료: ${result.length}건, 누락: ${missing.length}건`);
if (missing.length) console.log('누락 번호:', missing.join(', '));
