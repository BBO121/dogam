async function initSidebar() {
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;

  const path = window.location.pathname.split('/').pop();
  const isLocal = ['localhost', '127.0.0.1'].includes(window.location.hostname);

  sidebar.innerHTML = `
    <div class="sidebar-user-block" id="sidebarUserBlock"></div>

    <nav class="sidebar-menu">
      <a href="index.html"  class="sidebar-item ${path === 'index.html' ? 'active' : ''}">홈</a>
      <a href="notice.html" class="sidebar-item ${path === 'notice.html' || path === 'notice-detail.html' ? 'active' : ''}">공지사항</a>
    </nav>

    <div class="sidebar-accordion" id="accNotes">
      <button class="sidebar-accordion-btn" onclick="toggleAccordion('accNotes')">
        연구소 노트<span class="sidebar-accordion-arrow" id="arrNotes"></span>
      </button>
      <div class="sidebar-accordion-body" id="bodyNotes">
        <a href="update-note.html" class="sidebar-subitem ${path === 'update-note.html' || path === 'update-note-detail.html' || path === 'update-note-write.html' ? 'active' : ''}">업데이트</a>
        <a href="dev-log.html"     class="sidebar-subitem ${path === 'dev-log.html' || path === 'dev-log-detail.html' || path === 'dev-log-write.html' ? 'active' : ''}">개발일지</a>
      </div>
    </div>

    <nav class="sidebar-menu">
      <a href="guide.html" class="sidebar-item ${path === 'guide.html' || path === 'guide-detail.html' ? 'active' : ''}">가이드</a>
    </nav>

    <div class="sidebar-divider"></div>

    <div class="sidebar-accordion" id="accSpecies">
      <button class="sidebar-accordion-btn" id="btnSpecies" onclick="onSpeciesClick(this)">
        종족<span class="sidebar-accordion-arrow" id="arrSpecies"></span>
      </button>
      <div class="sidebar-accordion-body" id="bodySpecies">
        <p class="sidebar-loading">불러오는 중...</p>
      </div>
    </div>

    <a href="character-list.html" class="sidebar-accordion-btn ${path === 'character-list.html' || path === 'character.html' ? 'active' : ''}" style="text-decoration:none; display:flex; align-items:center;">개체</a>

    <a href="adoption.html" class="sidebar-accordion-btn ${path === 'adoption.html' || path === 'adoption-detail.html' || path === 'adoption-write.html' ? 'active' : ''}" style="text-decoration:none; display:flex; align-items:center;">분양</a>

    <a href="users.html" class="sidebar-accordion-btn ${path === 'users.html' || path === 'profile.html' && new URLSearchParams(window.location.search).get('user') ? 'active' : ''}" style="text-decoration:none; display:flex; align-items:center;">유저</a>

    <div class="sidebar-divider"></div>

    <nav class="sidebar-menu">
      <a href="my-species.html"    class="sidebar-item sidebar-login ${path === 'my-species.html'    ? 'active' : ''}">내 종족</a>
      <a href="my-characters.html" class="sidebar-item sidebar-login ${path === 'my-characters.html' ? 'active' : ''}">내 캐릭터</a>
      <a href="my-designs.html"    class="sidebar-item sidebar-login ${path === 'my-designs.html'    ? 'active' : ''}">내 디자인</a>
      <a href="my-slots.html"      class="sidebar-item sidebar-login ${path === 'my-slots.html'      ? 'active' : ''}">내 디자인권</a>
      <a href="my-adoptions.html" class="sidebar-item sidebar-login ${path === 'my-adoptions.html' ? 'active' : ''}">내 분양</a>
      <!-- 메시지: 추후 활성화 예정
      <a href="messages.html"      class="sidebar-item sidebar-login ${path === 'messages.html' || path === 'chat.html' ? 'active' : ''}">메시지</a>
      -->
      <div class="sidebar-accordion sidebar-login" id="accMyInfo">
        <button class="sidebar-accordion-btn" onclick="toggleAccordion('accMyInfo')">
          내 정보<span class="sidebar-accordion-arrow" id="arrMyInfo"></span>
        </button>
        <div class="sidebar-accordion-body" id="bodyMyInfo">
          <a href="profile.html"           class="sidebar-subitem ${path === 'profile.html'           ? 'active' : ''}">내 프로필</a>
          <a href="transfer-history.html" class="sidebar-subitem ${path === 'transfer-history.html' ? 'active' : ''}">캐릭터 이전 내역</a>
        </div>
      </div>
      <a href="my-wallet.html" class="sidebar-item sidebar-login ${path === 'my-wallet.html' ? 'active' : ''}">내 지갑</a>
      <a href="notifications.html" class="sidebar-item sidebar-login ${path === 'notifications.html' ? 'active' : ''}" style="justify-content:space-between;">
        알림<span class="sidebar-notif-badge" id="sidebarNotifBadge" style="display:none">0</span>
      </a>
    </nav>

    <div class="sidebar-divider"></div>

    <nav class="sidebar-menu">
      <a href="species-apply.html" class="sidebar-item ${path === 'species-apply.html' || path === 'species-apply-write.html' || path === 'species-apply-detail.html' ? 'active' : ''}" style="justify-content:space-between;">✨종족주 신청✨<span class="sidebar-notif-badge" id="sidebarApplyBadge" style="display:none">0</span></a>
      <a href="inquiry.html"    class="sidebar-item ${path === 'inquiry.html' || path === 'inquiry-write.html' || path === 'inquiry-detail.html' ? 'active' : ''}" style="justify-content:space-between;">문의<span class="sidebar-notif-badge" id="sidebarInquiryBadge" style="display:none">0</span></a>
      <a href="bug-report.html" class="sidebar-item ${path === 'bug-report.html' || path === 'bug-report-write.html' || path === 'bug-report-detail.html' ? 'active' : ''}" style="justify-content:space-between;">버그리포트<span class="sidebar-notif-badge" id="sidebarBugBadge" style="display:none">0</span></a>
    </nav>
  `;

  // 연구소 노트 하위 페이지면 아코디언 자동 열기
  const notePages = ['update-note.html','update-note-detail.html','update-note-write.html',
                     'dev-log.html','dev-log-detail.html','dev-log-write.html'];
  if (notePages.includes(path)) {
    document.getElementById('bodyNotes').classList.add('open');
    document.getElementById('arrNotes').style.transform = 'rotate(180deg)';
  }

  // 종족 관련 페이지: 버튼 active 표시 (모바일/PC 공통)
  if (path === 'species.html' || path === 'species-list.html') {
    document.getElementById('btnSpecies')?.classList.add('active');
  }

  // 내 정보 하위 페이지면 아코디언 자동 열기
  if (path === 'profile.html' || path === 'transfer-history.html') {
    document.getElementById('bodyMyInfo').classList.add('open');
    document.getElementById('arrMyInfo').style.transform = 'rotate(180deg)';
  }

  // 플라이아웃 패널 주입 (PC 전용)
  if (!document.getElementById('flyoutSpecies')) {
    const el = document.createElement('div');
    el.id = 'flyoutSpecies';
    el.className = 'species-flyout';
    document.body.appendChild(el);
  }

  // 바텀시트 주입 (모바일 전용)
  if (!document.getElementById('speciesSheetOverlay')) {
    const overlay = document.createElement('div');
    overlay.id = 'speciesSheetOverlay';
    overlay.className = 'species-sheet-overlay';
    overlay.addEventListener('click', dismissSpeciesSheet);
    document.body.appendChild(overlay);

    const panel = document.createElement('div');
    panel.id = 'speciesSheetPanel';
    panel.className = 'species-sheet-panel';
    document.body.appendChild(panel);
  }

  loadSpeciesSidebar();
  updateSidebarLogin();
  loadAdminBadges();
  initHamburger();
}

function initHamburger() {
  // 햄버거 버튼 주입
  const headerInner = document.querySelector('.header-inner');
  if (headerInner && !document.getElementById('hamburgerBtn')) {
    const btn = document.createElement('button');
    btn.id = 'hamburgerBtn';
    btn.className = 'hamburger-btn';
    btn.setAttribute('aria-label', '메뉴 열기');
    btn.innerHTML = '<span></span><span></span><span></span>';
    btn.addEventListener('click', toggleSidebar);
    headerInner.prepend(btn);
  }

  // 오버레이 주입
  if (!document.getElementById('sidebarOverlay')) {
    const overlay = document.createElement('div');
    overlay.id = 'sidebarOverlay';
    overlay.className = 'sidebar-overlay';
    overlay.addEventListener('click', closeSidebar);
    document.body.appendChild(overlay);
  }

  // 사이드바 링크 클릭 시 닫기 (모바일, 아코디언 버튼 제외)
  const sidebar = document.getElementById('sidebar');
  if (sidebar) {
    sidebar.querySelectorAll('a, button').forEach(el => {
      el.addEventListener('click', () => {
        if (window.innerWidth <= 767 && !el.classList.contains('sidebar-accordion-btn')) {
          closeSidebar();
        }
      });
    });
  }
}

function toggleSidebar() {
  const sidebar = document.getElementById('sidebar');
  const btn     = document.getElementById('hamburgerBtn');
  const overlay = document.getElementById('sidebarOverlay');
  if (!sidebar) return;

  const isOpen = sidebar.classList.toggle('sidebar--open');
  if (btn)     btn.classList.toggle('is-open', isOpen);
  if (overlay) overlay.classList.toggle('show', isOpen);
  document.body.style.overflow = isOpen ? 'hidden' : '';
}

function closeSidebar() {
  const sidebar = document.getElementById('sidebar');
  const btn     = document.getElementById('hamburgerBtn');
  const overlay = document.getElementById('sidebarOverlay');
  if (sidebar) sidebar.classList.remove('sidebar--open');
  if (btn)     btn.classList.remove('is-open');
  if (overlay) overlay.classList.remove('show');
  document.body.style.overflow = '';
}

// 초성/문자 그룹 반환
function getSpeciesGroup(name) {
  const ch   = name?.[0] || '';
  const code = ch.charCodeAt(0);
  if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) return 'A-Z';
  if (code >= 0xAC00 && code <= 0xD7A3) {
    const cho = ['ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
    return cho[Math.floor((code - 0xAC00) / (21 * 28))];
  }
  return '#';
}

const FLYOUT_GROUP_ORDER = ['A-Z','ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ','#'];

async function loadSpeciesSidebar() {
  const body       = document.getElementById('bodySpecies');
  const flyout     = document.getElementById('flyoutSpecies');
  const sheetPanel = document.getElementById('speciesSheetPanel');
  if (!body) return;

  const { data, error } = await sb.from('species').select('id, name').order('name');

  const q    = new URLSearchParams(window.location.search);
  const curr = q.get('id');

  const allLink       = `<a href="species-list.html" class="sidebar-subitem sidebar-subitem--all">전체보기</a>`;
  const allLinkFlyout = `<a href="species-list.html" class="flyout-all-link">전체보기</a>`;

  // ── 모바일 아코디언 body (숨겨져 있으나 혹시 모를 대비) ──
  if (error || !data || data.length === 0) {
    body.innerHTML = allLink;
  } else {
    body.innerHTML = allLink + data.map(s =>
      `<a href="species.html?id=${s.id}" class="sidebar-subitem ${curr === String(s.id) ? 'active' : ''}">${s.name}</a>`
    ).join('');
  }

  // ── 플라이아웃·바텀시트 공용 그룹화 HTML ──────────────────
  let groupedHtml = allLinkFlyout;
  if (error || !data || data.length === 0) {
    const dummy = ['드래곤','엘프','요정','늑대인간','슬라임','골렘'];
    groupedHtml += dummy.map(n =>
      `<a href="species-list.html" class="sidebar-subitem" style="opacity:0.45;">${n}</a>`
    ).join('');
  } else {
    const groups = {};
    data.forEach(s => {
      const g = getSpeciesGroup(s.name);
      (groups[g] = groups[g] || []).push(s);
    });
    FLYOUT_GROUP_ORDER.forEach(g => {
      if (!groups[g]) return;
      groupedHtml += `<div class="flyout-group-label">${g}</div>`;
      groupedHtml += groups[g].map(s =>
        `<a href="species.html?id=${s.id}" class="sidebar-subitem ${curr === String(s.id) ? 'active' : ''}">${s.name}</a>`
      ).join('');
    });
  }

  const searchHtml = `<div class="flyout-search-wrap"><input type="text" class="flyout-search-input" placeholder="종족 검색..."></div>`;
  const scrollWrapOpen  = '<div class="flyout-scroll-body">';
  const scrollWrapClose = '</div>';

  // 플라이아웃 (PC)
  if (flyout) {
    flyout.innerHTML = searchHtml + scrollWrapOpen + groupedHtml + scrollWrapClose;
    const input = flyout.querySelector('.flyout-search-input');
    const scrollBody = flyout.querySelector('.flyout-scroll-body');
    input.addEventListener('input', () => filterFlyout(scrollBody, input.value));
    flyout.querySelectorAll('a').forEach(el => {
      el.addEventListener('click', () => { if (window.innerWidth >= 768) closeFlyout(); });
    });
  }

  // 바텀시트 (모바일)
  if (sheetPanel) {
    sheetPanel.innerHTML = '<div class="species-sheet-handle"></div>' + searchHtml + scrollWrapOpen + groupedHtml + scrollWrapClose;
    const input = sheetPanel.querySelector('.flyout-search-input');
    const scrollBody = sheetPanel.querySelector('.flyout-scroll-body');
    input.addEventListener('input', () => filterFlyout(scrollBody, input.value));
    sheetPanel.querySelectorAll('a').forEach(el => {
      el.addEventListener('click', closeSpeciesSheet);
    });
  }
}

async function updateSidebarLogin() {
  const user = await getUser();
  const block = document.getElementById('sidebarUserBlock');

  if (user) {
    document.querySelectorAll('.sidebar-login').forEach(el => el.classList.remove('sidebar-login'));

    if (block) {
      const nickname = user.user_metadata?.display_name || user.user_metadata?.nickname || '유저';
      const admin = user.user_metadata?.role === 'admin';
      const staff = user.user_metadata?.role === 'staff';
      const TESTERS = ['Moulow', 'moulow', 'Sawol'];
      const isTester = TESTERS.includes(nickname);
      const roleIsSpeciesOwner = user.user_metadata?.role === 'species_owner';
      const isSpeciesOwner = await window._cachedIsSpeciesOwner?.(user.id, roleIsSpeciesOwner) ?? roleIsSpeciesOwner;

      const badges = [];
      if (admin)                                        badges.push(`<a href="admin.html" class="badge-admin">관리자</a>`);
      if (staff)                                        badges.push(`<a href="admin.html" class="badge-staff">스태프</a>`);
      if (isTester && !staff)                           badges.push(`<span style="font-size:10px;padding:3px 8px;background:#dcfce7;color:#166534;border-radius:4px;font-weight:700;">테스터</span>`);
      if (isSpeciesOwner)                               badges.push(`<span class="badge-role">종족주</span>`);
      if (!admin && !staff && !isTester && !isSpeciesOwner) badges.push(`<span class="badge-user">일반유저</span>`);

      block.innerHTML = `
        <div class="sidebar-user-row">
          <a href="profile.html" class="btn-username">${nickname}</a>
          ${badges.join('')}
        </div>
        <button class="btn-logout" onclick="signOut()">로그아웃</button>
      `;
    }
  } else {
    if (block) {
      block.innerHTML = `<a href="login.html" class="btn-login">로그인</a>`;
    }
  }
}

// ── 종족 플라이아웃 (PC 전용) ─────────────────────────
function onSpeciesClick(btn) {
  if (window.innerWidth < 768) {
    closeSidebar();
    openSpeciesSheet();
  } else {
    const flyout = document.getElementById('flyoutSpecies');
    if (flyout && flyout.classList.contains('open')) {
      closeFlyout();
    } else {
      openFlyout(btn);
    }
  }
}

function resetFlyoutSearch(container) {
  const input = container?.querySelector('.flyout-search-input');
  if (input && input.value) {
    input.value = '';
    const scrollBody = container.querySelector('.flyout-scroll-body');
    if (scrollBody) filterFlyout(scrollBody, '');
  }
}

function openFlyout(btn) {
  const flyout = document.getElementById('flyoutSpecies');
  if (!flyout) return;

  resetFlyoutSearch(flyout);
  const rect = btn.getBoundingClientRect();
  flyout.style.top  = rect.top + 'px';
  flyout.style.left = (rect.right + 6) + 'px';
  flyout.classList.add('open');

  // 뷰포트 하단 벗어나면 위로 조정
  const fr = flyout.getBoundingClientRect();
  if (fr.bottom > window.innerHeight - 12) {
    flyout.style.top = Math.max(12, window.innerHeight - fr.height - 12) + 'px';
  }

  btn.classList.add('flyout-open');
  setTimeout(() => document.addEventListener('click', onFlyoutOutsideClick), 0);
}

function closeFlyout() {
  const flyout = document.getElementById('flyoutSpecies');
  const btn    = document.getElementById('btnSpecies');
  if (flyout) flyout.classList.remove('open');
  if (btn)    btn.classList.remove('flyout-open');
  document.removeEventListener('click', onFlyoutOutsideClick);
}

function openSpeciesSheet() {
  const overlay = document.getElementById('speciesSheetOverlay');
  const panel   = document.getElementById('speciesSheetPanel');
  if (overlay) overlay.classList.add('show');
  if (panel) {
    resetFlyoutSearch(panel);
    panel.classList.add('open');
    const scrollBody = panel.querySelector('.flyout-scroll-body');
    if (scrollBody) scrollBody.scrollTop = 0;
  }
  document.body.style.overflow = 'hidden';
}

function closeSpeciesSheet() {
  const overlay = document.getElementById('speciesSheetOverlay');
  const panel   = document.getElementById('speciesSheetPanel');
  if (overlay) overlay.classList.remove('show');
  if (panel)   panel.classList.remove('open');
  document.body.style.overflow = '';
}

function dismissSpeciesSheet() {
  closeSpeciesSheet();
  toggleSidebar();
}

function filterFlyout(scrollBody, query) {
  const q = query.trim().toLowerCase();
  const items  = scrollBody.querySelectorAll('.sidebar-subitem');
  const labels = scrollBody.querySelectorAll('.flyout-group-label');

  if (!q) {
    items.forEach(el => el.style.display = '');
    labels.forEach(el => el.style.display = '');
    const empty = scrollBody.querySelector('.flyout-empty');
    if (empty) empty.remove();
    return;
  }

  items.forEach(el => {
    if (el.classList.contains('sidebar-subitem--all') || el.classList.contains('flyout-all-link')) {
      el.style.display = '';
    } else {
      el.style.display = el.textContent.toLowerCase().includes(q) ? '' : 'none';
    }
  });

  labels.forEach(label => {
    let next = label.nextElementSibling;
    let hasVisible = false;
    while (next && !next.classList.contains('flyout-group-label')) {
      if (next.tagName === 'A' && next.style.display !== 'none') { hasVisible = true; break; }
      next = next.nextElementSibling;
    }
    label.style.display = hasVisible ? '' : 'none';
  });

  const allHidden = [...items].filter(el =>
    !el.classList.contains('sidebar-subitem--all') && !el.classList.contains('flyout-all-link')
  ).every(el => el.style.display === 'none');

  let empty = scrollBody.querySelector('.flyout-empty');
  if (allHidden) {
    if (!empty) {
      empty = document.createElement('p');
      empty.className = 'flyout-empty';
      empty.textContent = '검색 결과가 없어요.';
      scrollBody.appendChild(empty);
    }
  } else {
    if (empty) empty.remove();
  }
}

function onFlyoutOutsideClick(e) {
  const flyout = document.getElementById('flyoutSpecies');
  const btn    = document.getElementById('btnSpecies');
  if (flyout && btn && !flyout.contains(e.target) && !btn.contains(e.target)) {
    closeFlyout();
  }
}

function toggleAccordion(id) {
  const suffix  = id.replace('acc', '');
  const body    = document.getElementById('body' + suffix);
  const arrow   = document.getElementById('arr'  + suffix);
  if (!body) return;

  const isOpen = body.classList.toggle('open');
  if (arrow) arrow.style.transform = isOpen ? 'rotate(180deg)' : '';
}

async function loadAdminBadges() {
  const user = await getUser();
  if (!isAdminOrStaff(user?.user_metadata?.role)) return;

  const [{ count: inquiryCount }, { count: bugCount }, { count: applyCount }] = await Promise.all([
    sb.from('inquiries').select('*', { count: 'exact', head: true }).eq('status', '접수됨'),
    sb.from('bug_reports').select('*', { count: 'exact', head: true }).eq('status', '접수됨'),
    sb.from('species_applications').select('*', { count: 'exact', head: true }).in('status', ['접수됨', '검토중']),
  ]);

  const iBadge = document.getElementById('sidebarInquiryBadge');
  const bBadge = document.getElementById('sidebarBugBadge');
  const aBadge = document.getElementById('sidebarApplyBadge');

  if (iBadge && inquiryCount > 0) {
    iBadge.textContent  = inquiryCount > 99 ? '99+' : inquiryCount;
    iBadge.style.display = 'inline-flex';
  }
  if (bBadge && bugCount > 0) {
    bBadge.textContent  = bugCount > 99 ? '99+' : bugCount;
    bBadge.style.display = 'inline-flex';
  }
  if (aBadge && applyCount > 0) {
    aBadge.textContent  = applyCount > 99 ? '99+' : applyCount;
    aBadge.style.display = 'inline-flex';
  }
}

document.addEventListener('DOMContentLoaded', initSidebar);

// ── 가이드맵 동적 로드 (미구현, 추후 연결 예정) ────────────────────────────────
// function _loadGuideTour() {
//   if (typeof openCategoryModal !== 'undefined') return;
//   const s = document.createElement('script');
//   s.src = '../js/guide-tour.js';
//   document.head.appendChild(s);
// }
// document.addEventListener('DOMContentLoaded', _loadGuideTour);

function openGuideTour() {
  // guide-tour.js 미구현 — 추후 연결 예정
  // if (typeof openCategoryModal === 'function') {
  //   openCategoryModal();
  //   return;
  // }
  // const s = document.createElement('script');
  // s.src = '../js/guide-tour.js';
  // s.onload = () => openCategoryModal();
  // document.head.appendChild(s);
}
