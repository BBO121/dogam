let _user              = null;
let _equippedFrameId   = null;
let _equippedStickerId = null;
let _itemsByType       = {};

// DB의 style_key → CSS 클래스 매핑
// (DB 연동 전 로컬 더미 대비 폴백)
const STYLE_KEY_MAP = {
  'frame-mint':            'frame-mint',
  'frame-orange':          'frame-orange',
  'frame-simple-sky':      'frame-simple-sky',
  'frame-simple-lavender': 'frame-simple-lavender',
  'frame-simple-rose':     'frame-simple-rose',
  'frame-simple-lemon':    'frame-simple-lemon',
  'frame-simple-lime':     'frame-simple-lime',
  'frame-simple-gray':     'frame-simple-gray',
};

const TYPE_LABEL = {
  frame:        '프레임',
  sticker:      '스티커',
  title:        '칭호',
  profile_deco: '프로필 꾸미기',
};

// ── 초기화 ──────────────────────────────────────────────
async function initPage() {
  try {
    _user = await getUser();
    if (!_user) { window.location.href = 'login.html'; return; }

    await loadData();
    renderBag();

    document.getElementById('pageLoading').style.display = 'none';
    document.getElementById('pageContent').style.display = '';
  } catch (e) {
    console.error('[my-bag] initPage 오류:', e);
    document.getElementById('pageLoading').textContent = '불러오기 실패. 새로고침 해주세요.';
  }
}

async function loadData() {
  console.log('[my-bag] loadData 시작, user.id =', _user.id);

  const [userItemsRes, equipRes] = await Promise.all([
    sb.from('user_items')
      .select('item_id, purchased_at')
      .eq('user_id', _user.id),
    sb.from('user_equipment')
      .select('equipped_frame_id, equipped_sticker_id')
      .eq('user_id', _user.id)
      .maybeSingle(),
  ]);

  console.log('[my-bag] user_items 조회 결과:', userItemsRes.data, '에러:', userItemsRes.error);

  _equippedFrameId   = equipRes.data?.equipped_frame_id   ?? null;
  _equippedStickerId = equipRes.data?.equipped_sticker_id ?? null;

  const userItems = userItemsRes.data || [];
  _itemsByType = {};
  if (!userItems.length) {
    console.log('[my-bag] 보유 아이템 없음 → 종료');
    return;
  }

  const itemIds = userItems.map(r => r.item_id);
  console.log('[my-bag] item_id 목록:', itemIds);

  const { data: shopItemsData, error: shopErr } = await sb.from('shop_items')
    .select('id, name, description, item_type, style_key, image_url, sub_category, sort_order')
    .in('id', itemIds)
    .order('sort_order', { ascending: true });

  console.log('[my-bag] shop_items 조회 결과:', shopItemsData, '에러:', shopErr);

  const shopMap = {};
  (shopItemsData || []).forEach(item => { shopMap[item.id] = item; });

  // _itemsByType = { type: { sub_category: [items] } }
  userItems.forEach(row => {
    const item = shopMap[row.item_id];
    if (!item) {
      console.warn('[my-bag] item_id에 해당하는 shop_items 없음:', row.item_id);
      return;
    }
    const type = item.item_type || 'etc';
    const sub  = item.sub_category || '기본';
    if (!_itemsByType[type])      _itemsByType[type] = {};
    if (!_itemsByType[type][sub]) _itemsByType[type][sub] = [];
    _itemsByType[type][sub].push({ ...item });
  });
}

// ── 착용 프레임 미리보기 렌더 ────────────────────────────
function renderEquippedPreview() {
  const el = document.getElementById('equippedPreview');
  if (!el) return;

  const frames        = Object.values(_itemsByType['frame']   || {}).flat();
  const stickers      = Object.values(_itemsByType['sticker'] || {}).flat();
  const equippedFrame   = _equippedFrameId   ? frames.find(f => f.id === _equippedFrameId)   : null;
  const equippedSticker = _equippedStickerId ? stickers.find(s => s.id === _equippedStickerId) : null;

  if (!equippedFrame && !equippedSticker) {
    el.innerHTML = `
      <div class="bag-ep-section">
        <h2 class="bag-section-title">미리보기</h2>
        <p class="bag-ep-none">착용 중인 아이템이 없습니다</p>
      </div>`;
    return;
  }

  const avatarUrl   = _user?.user_metadata?.avatar_url || '';
  const avatarStyle = avatarUrl
    ? `background-image:url('${avatarUrl}');background-size:cover;background-position:center;`
    : '';
  const frameCss = equippedFrame ? (STYLE_KEY_MAP[equippedFrame.style_key] || '') : '';

  const stickerOverlay = equippedSticker
    ? `<img id="bagEpStickerImg" src="${equippedSticker.image_url}" alt="${equippedSticker.name}"
           style="grid-area:1/1; width:0; height:0; object-fit:contain; z-index:3; pointer-events:none;">`
    : '';

  const leftHtml = equippedFrame
    ? `<div class="bag-ep-side bag-ep-side--left">
        <span class="bag-ep-item-label">프레임</span>
        <p class="bag-ep-name">${equippedFrame.name}</p>
        <button class="bag-unequip-btn" onclick="unequipFrame()">해제하기</button>
      </div>`
    : `<div class="bag-ep-side bag-ep-side--left"></div>`;

  const rightHtml = equippedSticker
    ? `<div class="bag-ep-side bag-ep-side--right">
        <span class="bag-ep-item-label">스티커</span>
        <p class="bag-ep-name">${equippedSticker.name}</p>
        <button class="bag-unequip-btn" onclick="unequipSticker()">해제하기</button>
      </div>`
    : `<div class="bag-ep-side bag-ep-side--right"></div>`;

  el.innerHTML = `
    <div class="bag-ep-section">
      <h2 class="bag-section-title">미리보기</h2>
      <div class="bag-ep-tricolumn">
        ${leftHtml}
        <div style="display:grid; place-items:center; flex-shrink:0; line-height:0;">
          <div class="bag-ep-preview-wrap ${frameCss}" style="grid-area:1/1;">
            <div class="bag-ep-avatar" style="${avatarStyle}"></div>
          </div>
          ${stickerOverlay}
        </div>
        ${rightHtml}
      </div>
    </div>`;

  // 렌더 후 실제 아바타 크기 측정 → 스티커 비율 계산 (1168×1168, 프로필영역 768, 마진 200)
  if (equippedSticker) {
    requestAnimationFrame(() => {
      const wrap = el.querySelector('.bag-ep-preview-wrap');
      const img  = document.getElementById('bagEpStickerImg');
      if (!wrap || !img) return;
      // clientWidth = 콘텐츠 너비만 (border 제외) → 96px → 146px (프로필과 동일 비율)
      const avatarPx  = wrap.clientWidth;
      const stickerPx = Math.round(avatarPx * 1168 / 768);
      img.style.width  = stickerPx + 'px';
      img.style.height = stickerPx + 'px';
    });
  }
}

// ── 가방 렌더 ────────────────────────────────────────────
function renderBag() {
  renderEquippedPreview();

  const wrap = document.getElementById('bagSections');
  const types = Object.keys(_itemsByType);

  if (!types.length) {
    wrap.innerHTML = `<p class="empty-state" style="padding:60px 0; text-align:center;">보유한 아이템이 없어요.<br><a href="shop.html" style="color:var(--sky-dark); font-weight:700;">상점 바로가기</a></p>`;
    return;
  }

  wrap.innerHTML = types.map(type => {
    const subs      = _itemsByType[type];
    const label     = TYPE_LABEL[type] || type;
    const subEntries = Object.entries(subs);
    const multiSub  = subEntries.length > 1;

    return `
      <div class="bag-section">
        <h2 class="bag-section-title">${label}</h2>
        ${subEntries.map(([subLabel, items], i) => `
          <div class="${i > 0 ? 'bag-subsection-gap' : ''}">
            ${multiSub ? `<h3 class="bag-subsection-title">${subLabel}</h3>` : ''}
            <div class="bag-grid">
              ${items.map(item => renderBagItem(item, type)).join('')}
            </div>
          </div>
        `).join('')}
      </div>`;
  }).join('');
}

// ── 아이템 카드 렌더 (상점과 동일한 크기/구조) ──────────────
function renderBagItem(item, type) {
  const styleKey   = item.style_key || '';
  const cssClass   = STYLE_KEY_MAP[styleKey] || '';
  const isEquipped = type === 'frame'
    ? item.id === _equippedFrameId
    : type === 'sticker'
      ? item.id === _equippedStickerId
      : false;

  const previewHtml = cssClass && type !== 'sticker'
    ? `<div class="frame-preview ${cssClass}"></div>`
    : item.image_url
      ? `<img src="${item.image_url}" alt="${item.name}"${type === 'sticker' ? ' class="shop-sticker-img"' : ''}>`
      : '';

  const badgeHtml = isEquipped
    ? `<span class="shop-thumb-badge shop-badge--owned shop-badge--right">착용중</span>`
    : '';

  let actionHtml;
  if (type === 'frame') {
    actionHtml = isEquipped
      ? `<span class="shop-thumb-status shop-status--owned">착용중</span>`
      : `<button class="bag-equip-btn-sm" data-item-id="${item.id}" onclick="equipFrame('${item.id}')">착용하기</button>`;
  } else if (type === 'sticker') {
    actionHtml = isEquipped
      ? `<span class="shop-thumb-status shop-status--owned">착용중</span>`
      : `<button class="bag-equip-btn-sm" data-item-id="${item.id}" onclick="equipSticker('${item.id}')">착용하기</button>`;
  } else {
    actionHtml = `<span class="shop-thumb-status shop-status--owned">보유중</span>`;
  }

  return `
    <div class="bag-item-card${isEquipped ? ' bag-item-card--equipped' : ''}">
      <div class="bag-item-preview">
        ${badgeHtml}
        ${previewHtml}
      </div>
      <p class="bag-item-name">${item.name}</p>
      <div class="bag-item-action">${actionHtml}</div>
    </div>`;
}

// ── 프레임 해제 ──────────────────────────────────────────
async function unequipFrame() {
  document.querySelectorAll('.bag-unequip-btn').forEach(btn => {
    btn.disabled = true; btn.textContent = '처리 중...';
  });

  const { data, error } = await sb.rpc('unequip_frame');

  if (error || !data?.success) {
    if (btn) { btn.disabled = false; btn.textContent = '해제하기'; }
    alert('해제 중 오류가 발생했습니다.');
    return;
  }

  _equippedFrameId = null;
  renderBag();
}

// ── 프레임 장착 ──────────────────────────────────────────
async function equipFrame(itemId) {
  const btn = document.querySelector(`.bag-equip-btn-sm[data-item-id="${itemId}"]`);
  if (btn) { btn.disabled = true; btn.textContent = '처리 중...'; }

  const { data, error } = await sb.rpc('equip_frame', { p_item_id: itemId });

  if (error || !data?.success) {
    if (btn) { btn.disabled = false; btn.textContent = '착용하기'; }
    console.error('[my-bag] equip_frame 오류:', error || data?.error);
    alert('장착 중 오류가 발생했습니다.');
    return;
  }

  _equippedFrameId = data.equipped_frame_id;
  renderBag();
}

// ── 스티커 해제 ──────────────────────────────────────────
async function unequipSticker() {
  document.querySelectorAll('.bag-unequip-btn').forEach(btn => {
    btn.disabled = true; btn.textContent = '처리 중...';
  });

  const { data, error } = await sb.rpc('unequip_sticker');

  if (error || !data?.success) {
    document.querySelectorAll('.bag-unequip-btn').forEach(btn => {
      btn.disabled = false; btn.textContent = '해제하기';
    });
    alert('해제 중 오류가 발생했습니다.');
    return;
  }

  _equippedStickerId = null;
  renderBag();
}

// ── 스티커 장착 ──────────────────────────────────────────
async function equipSticker(itemId) {
  const btn = document.querySelector(`.bag-equip-btn-sm[data-item-id="${itemId}"]`);
  if (btn) { btn.disabled = true; btn.textContent = '처리 중...'; }

  const { data, error } = await sb.rpc('equip_sticker', { p_item_id: itemId });

  if (error || !data?.success) {
    if (btn) { btn.disabled = false; btn.textContent = '착용하기'; }
    console.error('[my-bag] equip_sticker 오류:', error || data?.error);
    alert('장착 중 오류가 발생했습니다.');
    return;
  }

  _equippedStickerId = data.equipped_sticker_id;
  renderBag();
}

initPage();
