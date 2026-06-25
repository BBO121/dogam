let _user        = null;
let _wallet      = null;
let _ownedSet    = new Set();
let _pendingItem = null;
let _allItems    = [];

const CURRENCY_LABEL = { research_records: '연구기록', keys: '열쇠' };
const CURRENCY_ICON  = {
  research_records: `<img src="../images/icons/currency-record.png" class="shop-currency-icon" alt="연구기록">`,
  keys:             `<img src="../images/icons/currency-key.png"    class="shop-currency-icon" alt="열쇠">`,
};

const TYPE_LABEL = {
  frame:        '프레임',
  sticker:      '스티커',
  title:        '칭호',
  profile_deco: '프로필 꾸미기',
};

const ERROR_MSG = {
  NOT_AUTHENTICATED:    '로그인이 필요합니다.',
  ITEM_NOT_FOUND:       '존재하지 않는 상품입니다.',
  ITEM_NOT_AVAILABLE:   '현재 판매하지 않는 상품입니다.',
  ITEM_SALE_ENDED:      '판매가 종료된 상품입니다.',
  ALREADY_OWNED:        '이미 보유한 상품입니다.',
  WALLET_NOT_FOUND:     '지갑 정보를 찾을 수 없습니다.',
  INSUFFICIENT_BALANCE: '재화가 부족합니다.',
};

// ── 초기화 ──────────────────────────────────────────────
async function initPage() {
  try {
    _user = await getUser();
    if (!_user) { window.location.href = 'login.html'; return; }

    await loadData();
    renderCategories();

    document.getElementById('pageLoading').style.display = 'none';
    document.getElementById('pageContent').style.display = '';
  } catch (e) {
    console.error('[shop] initPage 오류:', e);
    document.getElementById('pageLoading').textContent = '불러오기 실패. 새로고침 해주세요.';
  }
}

async function loadData() {
  const [itemsRes, walletRes, ownedRes] = await Promise.all([
    sb.from('shop_items')
      .select('*')
      .neq('status', 'hidden')
      .or(`sale_end_at.is.null,sale_end_at.gt.${new Date().toISOString()}`)
      .order('sort_order', { ascending: true })
      .order('created_at',  { ascending: true }),
    getMyWallet(_user.id),
    sb.from('user_items')
      .select('item_id')
      .eq('user_id', _user.id),
  ]);

  _allItems = itemsRes.data  || [];
  _wallet   = walletRes.data;
  _ownedSet = new Set((ownedRes.data || []).map(r => r.item_id));
}

// ── 카테고리 렌더 ────────────────────────────────────────
function renderCategories() {
  const wrap = document.getElementById('shopCategories');

  // item_type 기준으로 그룹핑
  const grouped = {};
  _allItems.forEach(item => {
    const t = item.item_type || 'etc';
    if (!grouped[t]) grouped[t] = {};

    // sub_category 컬럼 있으면 사용, 없으면 '기본'
    const sub = item.sub_category || '기본';
    if (!grouped[t][sub]) grouped[t][sub] = [];
    grouped[t][sub].push(item);
  });

  const types = Object.keys(grouped);
  if (!types.length) {
    wrap.innerHTML = '<p class="empty-state" style="padding:60px 0;text-align:center;">판매중인 상품이 없어요.</p>';
    return;
  }

  wrap.innerHTML = types.map(type => {
    const label = TYPE_LABEL[type] || type;
    const subs  = grouped[type];
    return `
      <div class="shop-cat-box">
        <h2 class="shop-cat-title">${label}</h2>
        <div class="shop-cat-inner">
          ${Object.entries(subs).map(([subLabel, items], i) => `
            <div class="shop-subcat${i > 0 ? ' shop-subcat--gap' : ''}">
              <h3 class="shop-subcat-title">${subLabel}</h3>
              <div class="shop-cat-grid">
                ${items.map(renderThumb).join('')}
              </div>
            </div>
          `).join('')}
        </div>
      </div>`;
  }).join('');
}

// ── 가격 HTML 생성 (이중 통화 지원) ────────────────────────
function buildPriceHtml(item, discountHtml = '') {
  const curIcon = CURRENCY_ICON[item.currency] ?? CURRENCY_LABEL[item.currency] ?? item.currency;
  let html = `${curIcon} ${discountHtml}${item.price.toLocaleString()}`;
  if (item.secondary_currency && item.secondary_price) {
    const secIcon = CURRENCY_ICON[item.secondary_currency] ?? CURRENCY_LABEL[item.secondary_currency] ?? item.secondary_currency;
    html += ` ${secIcon} ${item.secondary_price.toLocaleString()}`;
  }
  return html;
}

// ── 썸네일 렌더 ──────────────────────────────────────────
function getItemState(item) {
  if (_ownedSet.has(item.id))        return 'owned';
  if (item.status === 'coming_soon') return 'coming';
  const balance = item.currency === 'research_records'
    ? (_wallet?.research_records ?? 0) : (_wallet?.keys ?? 0);
  if (item.price > 0 && balance < item.price) return 'insufficient';
  if (item.secondary_currency && item.secondary_price) {
    const secBalance = item.secondary_currency === 'research_records'
      ? (_wallet?.research_records ?? 0) : (_wallet?.keys ?? 0);
    if (secBalance < item.secondary_price) return 'insufficient';
  }
  return 'available';
}

function renderThumb(item) {
  const state    = getItemState(item);
  const isFree   = item.price === 0;
  const curIcon  = CURRENCY_ICON[item.currency] ?? CURRENCY_LABEL[item.currency] ?? item.currency;

  const imgOverlay = state === 'owned'
    ? `<span class="shop-thumb-badge shop-badge--owned shop-badge--right">보유중</span>`
    : state === 'coming'
      ? `<span class="shop-thumb-badge shop-badge--coming">준비중</span>`
      : '';

  const previewHtml = item.style_key && item.item_type !== 'sticker'
    ? `<div class="frame-preview ${item.style_key}"></div>`
    : item.image_url
      ? `<img src="${item.image_url}" alt="${item.name}"${item.item_type === 'sticker' ? ' class="shop-sticker-img"' : ''}>`
      : '';

  const hasDiscount = item.original_price && item.original_price > item.price;
  const discountHtml = hasDiscount
    ? `<s class="shop-price-original">${item.original_price.toLocaleString()}</s> `
    : '';
  const priceHtml = buildPriceHtml(item, discountHtml);
  const statusHtml = {
    owned:        `<span class="shop-thumb-status shop-status--owned">보유중</span>`,
    coming:       `<span class="shop-thumb-status shop-status--coming">준비중</span>`,
    available:    `<span class="shop-thumb-status shop-status--available">${priceHtml}</span>`,
    insufficient: `<span class="shop-thumb-status shop-status--insufficient">${priceHtml}</span>`,
  }[state];

  // item 전달 시 실제 DB UUID 사용
  const itemJson = JSON.stringify(item).replace(/'/g, "\\'");

  return `
    <div class="shop-thumb shop-thumb--${state}"
         onclick='openDetailModal(${itemJson})'>
      <div class="shop-thumb-img">
        ${imgOverlay}
        ${previewHtml}
      </div>
      <p class="shop-thumb-name">${item.name}</p>
      ${statusHtml}
    </div>`;
}

// ── 상세 모달 ────────────────────────────────────────────
function openDetailModal(item) {
  const state    = getItemState(item);
  const isFree   = item.price === 0;
  const curIcon  = CURRENCY_ICON[item.currency] ?? CURRENCY_LABEL[item.currency] ?? item.currency;

  const previewEl = document.getElementById('detailPreview');
  previewEl.innerHTML = item.style_key && item.item_type !== 'sticker'
    ? `<div class="frame-preview frame-preview--lg ${item.style_key}"></div>`
    : item.image_url
      ? `<img src="${item.image_url}" alt="${item.name}" style="width:100%;height:100%;object-fit:${item.item_type === 'sticker' ? 'contain' : 'cover'};">`
      : '';

  document.getElementById('detailName').textContent  = item.name;
  document.getElementById('detailDesc').textContent  = item.description || '';

  const saleEndEl = document.getElementById('detailSaleEnd');
  if (saleEndEl) {
    if (item.sale_end_at) {
      const endDate = new Date(item.sale_end_at);
      const formatted = `${endDate.getFullYear()}년 ${endDate.getMonth() + 1}월 ${endDate.getDate()}일까지 판매`;
      saleEndEl.textContent = '⏰ ' + formatted;
      saleEndEl.style.display = '';
    } else {
      saleEndEl.style.display = 'none';
    }
  }

  const creditEl = document.getElementById('detailCredit');
  if (creditEl) {
    creditEl.textContent    = item.credit ? `Design by ${item.credit}` : '';
    creditEl.style.display  = item.credit ? '' : 'none';
  }
  const detailDiscount = item.original_price && item.original_price > item.price
    ? `<s class="shop-price-original">${item.original_price.toLocaleString()}</s> `
    : '';
  const detailPriceHtml = buildPriceHtml(item, detailDiscount);
  document.getElementById('detailPrice').innerHTML =
    state === 'insufficient'
      ? `<span style="color:#ef4444;">${detailPriceHtml}</span>`
      : detailPriceHtml;

  const actionEl = document.getElementById('detailAction');
  if (state === 'owned') {
    actionEl.innerHTML = `<span class="shop-detail-status shop-status--owned">보유중</span>`;
  } else if (state === 'coming') {
    actionEl.innerHTML = `<span class="shop-detail-status shop-status--coming">준비중</span>`;
  } else if (state === 'available') {
    const encoded = JSON.stringify(item).replace(/"/g, '&quot;');
    actionEl.innerHTML = `<button class="shop-buy-btn-lg"
      onclick='closeDetailModal(); openShopModal(JSON.parse(this.dataset.item))'
      data-item="${encoded}">구매하기</button>`;
  } else {
    actionEl.innerHTML = `<span class="shop-detail-status shop-status--insufficient">재화 부족</span>`;
  }

  document.getElementById('shopDetailModal').style.display = 'flex';
}

function closeDetailModal() {
  document.getElementById('shopDetailModal').style.display = 'none';
}

// ── 구매 확인 모달 ────────────────────────────────────────
function openShopModal(item) {
  _pendingItem = typeof item === 'string' ? JSON.parse(item) : item;
  const confirmPriceHtml = buildPriceHtml(_pendingItem);

  document.getElementById('shopModalDesc').innerHTML = `
    <div class="wallet-confirm-row">
      <span class="wallet-confirm-label">상품</span>
      <span class="wallet-confirm-value">${_pendingItem.name}</span>
    </div>
    <div class="wallet-confirm-row">
      <span class="wallet-confirm-label">가격</span>
      <span class="wallet-confirm-value wallet-confirm-amount">${confirmPriceHtml}</span>
    </div>`;

  const btn = document.getElementById('shopModalBtn');
  btn.disabled = false; btn.textContent = '구매';
  document.getElementById('shopModal').style.display = 'flex';
}

function closeShopModal() {
  document.getElementById('shopModal').style.display = 'none';
  _pendingItem = null;
}

// ── 구매 처리 ────────────────────────────────────────────
async function doPurchase() {
  if (!_pendingItem) return;
  const btn = document.getElementById('shopModalBtn');
  btn.disabled = true; btn.textContent = '처리 중...';

  // item.id = 실제 DB UUID
  const { data, error } = await sb.rpc('purchase_item', { p_item_id: _pendingItem.id });

  console.log('[shop] purchase result:', data);
  console.log('[shop] purchase error:', error);

  if (error || !data?.success) {
    btn.disabled = false; btn.textContent = '구매';
    alert(ERROR_MSG[data?.error] ?? `구매 중 오류가 발생했습니다.\n[${data?.error ?? error?.message ?? 'unknown'}]`);
    return;
  }

  _ownedSet.add(_pendingItem.id);
  if (_wallet) {
    if (data.currency === 'research_records') _wallet.research_records = data.new_balance;
    else _wallet.keys = data.new_balance;
    if (data.sec_new_balance !== undefined && _pendingItem.secondary_currency) {
      if (_pendingItem.secondary_currency === 'research_records') _wallet.research_records = data.sec_new_balance;
      else _wallet.keys = data.sec_new_balance;
    }
  }
  if (typeof updateHeaderCurrencyDisplay === 'function') {
    updateHeaderCurrencyDisplay({ research_records: _wallet?.research_records, keys: _wallet?.keys });
  }

  closeShopModal();
  renderCategories();
}

initPage();
