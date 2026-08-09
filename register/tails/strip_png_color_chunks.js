// PNG의 sRGB/gAMA/pHYs/iCCP 등 색상 프로파일 관련 청크를 제거해서
// "색상 프로파일을 확인해주세요" 류의 업로드 검증 오류를 방지한다.
// .NET System.Drawing으로 리사이즈하면 이 청크들이 자동으로 붙는데, 사이트 업로드 검증에서 거부당한다.
const fs = require('fs');

const STRIP_TYPES = new Set(['sRGB', 'gAMA', 'pHYs', 'iCCP', 'cHRM']);

function stripChunks(path) {
  const buf = fs.readFileSync(path);
  const sig = buf.subarray(0, 8);
  let offset = 8;
  const parts = [sig];
  let removed = [];
  while (offset < buf.length) {
    const len = buf.readUInt32BE(offset);
    const type = buf.toString('ascii', offset + 4, offset + 8);
    const chunkTotalLen = 8 + len + 4;
    const chunk = buf.subarray(offset, offset + chunkTotalLen);
    if (STRIP_TYPES.has(type)) {
      removed.push(type);
    } else {
      parts.push(chunk);
    }
    offset += chunkTotalLen;
  }
  const out = Buffer.concat(parts);
  fs.writeFileSync(path, out);
  return removed;
}

const files = process.argv.slice(2);
for (const f of files) {
  const removed = stripChunks(f);
  console.log(f, '->', removed.length ? `제거: ${removed.join(',')}` : '(해당 청크 없음)');
}
