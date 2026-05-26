// 이미지 압축 (최대 1200px, JPEG 0.82)
function compressImage(file, maxSize = 1200, quality = 0.82) {
  return new Promise((resolve) => {
    const img = new Image();
    const url = URL.createObjectURL(file);

    img.onload = () => {
      URL.revokeObjectURL(url);

      let { width, height } = img;
      if (width > maxSize || height > maxSize) {
        if (width > height) { height = Math.round(height * maxSize / width); width = maxSize; }
        else                { width = Math.round(width * maxSize / height); height = maxSize; }
      }

      const canvas = document.createElement('canvas');
      canvas.width  = width;
      canvas.height = height;
      canvas.getContext('2d').drawImage(img, 0, 0, width, height);

      canvas.toBlob(blob => resolve(blob), 'image/jpeg', quality);
    };

    img.src = url;
  });
}
