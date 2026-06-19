const ALLOWED_IMAGE_TYPES = ['image/png', 'image/gif', 'image/jpeg', 'image/webp'];
const MAX_IMAGE_DIMENSION  = 2000;
const MAX_BLOB_BYTES       = 2 * 1024 * 1024;

function compressImage(file, maxSize = 1200, quality = 0.82) {
  return new Promise((resolve, reject) => {
    if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
      reject(new Error('PNG, GIF, JPG, WebP 형식의 이미지만 업로드할 수 있어요.'));
      return;
    }

    // GIF: 애니메이션 보존을 위해 Canvas 변환 없이 원본 반환
    if (file.type === 'image/gif') {
      if (file.size > MAX_BLOB_BYTES) {
        reject(new Error('GIF 파일은 2MB 이하만 업로드할 수 있어요.'));
        return;
      }
      const gifReader = new FileReader();
      gifReader.onerror = () => reject(new Error('이미지 파일을 읽는 데 실패했어요.'));
      gifReader.onload = (e) => {
        const img = new Image();
        img.onerror = () => reject(new Error('이미지를 불러오는 데 실패했어요. 파일이 손상됐을 수 있어요.'));
        img.onload = () => {
          if (img.width > MAX_IMAGE_DIMENSION || img.height > MAX_IMAGE_DIMENSION) {
            reject(new Error(`이미지 해상도가 너무 커요. 최대 ${MAX_IMAGE_DIMENSION}×${MAX_IMAGE_DIMENSION}px까지 업로드할 수 있어요. (현재: ${img.width}×${img.height}px)`));
            return;
          }
          resolve(file);
        };
        img.src = e.target.result;
      };
      gifReader.readAsDataURL(file);
      return;
    }

    const reader = new FileReader();
    reader.onerror = () => reject(new Error('이미지 파일을 읽는 데 실패했어요.'));
    reader.onload = (e) => {
      const img = new Image();
      img.onerror = () => reject(new Error('이미지를 불러오는 데 실패했어요. 파일이 손상됐을 수 있어요.'));
      img.onload = () => {
        if (img.width > MAX_IMAGE_DIMENSION || img.height > MAX_IMAGE_DIMENSION) {
          reject(new Error(`이미지 해상도가 너무 커요. 최대 ${MAX_IMAGE_DIMENSION}×${MAX_IMAGE_DIMENSION}px까지 업로드할 수 있어요. (현재: ${img.width}×${img.height}px)`));
          return;
        }

        let { width, height } = img;
        if (width > maxSize || height > maxSize) {
          if (width > height) { height = Math.round(height * maxSize / width); width  = maxSize; }
          else                { width  = Math.round(width  * maxSize / height); height = maxSize; }
        }

        const canvas = document.createElement('canvas');
        canvas.width  = width;
        canvas.height = height;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#F8FAFC';
        ctx.fillRect(0, 0, width, height);
        ctx.drawImage(img, 0, 0, width, height);

        canvas.toBlob((blob) => {
          if (!blob) { reject(new Error('이미지 압축에 실패했어요.')); return; }
          if (blob.size <= MAX_BLOB_BYTES) { resolve(blob); return; }

          // 2MB 초과 시 품질 낮춰 재시도
          canvas.toBlob((blob2) => {
            if (!blob2) { reject(new Error('이미지 압축에 실패했어요.')); return; }
            if (blob2.size > MAX_BLOB_BYTES) {
              reject(new Error('압축 후에도 용량이 2MB를 초과해요. 더 작은 이미지를 사용해주세요.'));
              return;
            }
            resolve(blob2);
          }, 'image/jpeg', 0.65);
        }, 'image/jpeg', quality);
      };
      img.src = e.target.result;
    };
    reader.readAsDataURL(file);
  });
}

// Cropper.js 인스턴스 → 3:4 JPEG blob
function cropToBlob(cropper, maxSize = 600, quality = 0.85) {
  return new Promise((resolve, reject) => {
    const outH    = Math.round(maxSize * 4 / 3);
    const cropped = cropper.getCroppedCanvas({
      width: maxSize, height: outH,
      imageSmoothingEnabled: true, imageSmoothingQuality: 'high',
    });
    if (!cropped) { reject(new Error('크롭에 실패했어요.')); return; }

    // PNG 투명 배경 → 흰색으로 합성 후 JPEG 변환
    const canvas = document.createElement('canvas');
    canvas.width  = cropped.width;
    canvas.height = cropped.height;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#F8FAFC';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(cropped, 0, 0);

    canvas.toBlob(blob => {
      if (!blob) { reject(new Error('썸네일 생성에 실패했어요.')); return; }
      resolve(blob);
    }, 'image/jpeg', quality);
  });
}

// 이미지 blob + 워터마크 URL → 워터마크 합성 JPEG blob
function applyWatermark(imageBlob, watermarkUrl) {
  return new Promise((resolve, reject) => {
    const blobUrl = URL.createObjectURL(imageBlob);
    const img = new Image();
    const wm  = new Image();
    let imgReady = false, wmReady = false;

    function tryCompose() {
      if (!imgReady || !wmReady) return;
      try {
        const canvas = document.createElement('canvas');
        canvas.width  = img.naturalWidth;
        canvas.height = img.naturalHeight;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);
        ctx.drawImage(wm, 0, 0, canvas.width, canvas.height);
        canvas.toBlob(blob => {
          URL.revokeObjectURL(blobUrl);
          if (!blob) { reject(new Error('워터마크 합성에 실패했어요. (canvas tainted 또는 메모리 부족)')); return; }
          resolve(blob);
        }, 'image/jpeg', 0.90);
      } catch (e) {
        URL.revokeObjectURL(blobUrl);
        reject(new Error('워터마크 합성 오류: ' + e.message));
      }
    }

    img.onload  = () => { imgReady = true; tryCompose(); };
    img.onerror = () => { URL.revokeObjectURL(blobUrl); reject(new Error('이미지 로드에 실패했어요.')); };
    img.src = blobUrl;

    // 캐시버스팅으로 crossOrigin 캐시 충돌 방지
    const wmSrcWithBust = watermarkUrl + (watermarkUrl.includes('?') ? '&' : '?') + '_wm=' + Date.now();
    wm.crossOrigin = 'anonymous';
    wm.onload  = () => { wmReady = true; tryCompose(); };
    wm.onerror = () => { URL.revokeObjectURL(blobUrl); reject(new Error('워터마크 이미지를 불러오는 데 실패했어요: ' + watermarkUrl)); };
    wm.src = wmSrcWithBust;
  });
}

// 중앙 자동 크롭 (팝업 없이) → JPEG blob
function autoCenterCropToBlob(file, aspectRatio = 3/4, maxSize = 600, quality = 0.85) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('파일 읽기에 실패했어요.'));
    reader.onload = e => {
      const img = new Image();
      img.onerror = () => reject(new Error('이미지를 불러오는 데 실패했어요.'));
      img.onload = () => {
        const iw = img.width, ih = img.height;
        let cw, ch;
        if (iw / ih > aspectRatio) { ch = ih; cw = ih * aspectRatio; }
        else                       { cw = iw; ch = iw / aspectRatio; }
        const cx   = (iw - cw) / 2, cy = (ih - ch) / 2;
        const outH = Math.round(maxSize / aspectRatio);
        const canvas = document.createElement('canvas');
        canvas.width = maxSize; canvas.height = outH;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#F8FAFC';
        ctx.fillRect(0, 0, maxSize, outH);
        ctx.drawImage(img, cx, cy, cw, ch, 0, 0, maxSize, outH);
        canvas.toBlob(blob => {
          if (!blob) { reject(new Error('썸네일 생성에 실패했어요.')); return; }
          resolve(blob);
        }, 'image/jpeg', quality);
      };
      img.src = e.target.result;
    };
    reader.readAsDataURL(file);
  });
}
