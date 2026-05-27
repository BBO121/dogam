async function initSidebar() {
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;

  const path = window.location.pathname.split('/').pop();

  sidebar.innerHTML = `
    <nav class="sidebar-menu">
      <a href="index.html"        class="sidebar-item ${path === 'index.html' ? 'active' : ''}">홈</a>
      <a href="notice.html"       class="sidebar-item ${path === 'notice.html' || path === 'notice-detail.html' ? 'active' : ''}">공지사항</a>
      <a href="guide.html"        class="sidebar-item ${path === 'guide.html'  || path === 'guide-detail.html'  ? 'active' : ''}">가이드</a>
      <a href="adoption.html"     class="sidebar-item ${path === 'adoption.html' || path === 'adoption-detail.html' ? 'active' : ''}">분양</a>
    </nav>

    <div class="sidebar-divider"></div>

    <div class="sidebar-accordion" id="accSpecies">
      <button class="sidebar-accordion-btn" onclick="toggleAccordion('accSpecies')">
        종족<span class="sidebar-accordion-arrow" id="arrSpecies"></span>
      </button>
      <div class="sidebar-accordion-body" id="bodySpecies">
        <p class="sidebar-loading">불러오는 중...</p>
      </div>
    </div>

    <a href="character-list.html" class="sidebar-accordion-btn ${path === 'character-list.html' || path === 'character.html' ? 'active' : ''}" style="text-decoration:none; display:flex; align-items:center;">개체</a>

    <a href="users.html" class="sidebar-accordion-btn ${path === 'users.html' || path === 'profile.html' && new URLSearchParams(window.location.search).get('user') ? 'active' : ''}" style="text-decoration:none; display:flex; align-items:center;">유저</a>

    <div class="sidebar-divider"></div>

    <nav class="sidebar-menu">
      <a href="my-species.html"    class="sidebar-item sidebar-login ${path === 'my-species.html'    ? 'active' : ''}">내 종족</a>
      <a href="my-characters.html" class="sidebar-item sidebar-login ${path === 'my-characters.html' ? 'active' : ''}">내 캐릭터</a>
      <a href="my-adoptions.html" class="sidebar-item sidebar-login ${path === 'my-adoptions.html' ? 'active' : ''}">내 분양</a>
      <!-- 메시지: 추후 활성화 예정
      <a href="messages.html"      class="sidebar-item sidebar-login ${path === 'messages.html' || path === 'chat.html' ? 'active' : ''}">메시지</a>
      -->
      <div class="sidebar-accordion sidebar-login" id="accMyInfo">
        <button class="sidebar-accordion-btn" onclick="toggleAccordion('accMyInfo')">
          내 정보<span class="sidebar-accordion-arrow" id="arrMyInfo"></span>
        </button>
        <div class="sidebar-accordion-body" id="bodyMyInfo">
          <a href="profile.html"           class="sidebar-subitem ${path === 'profile.html'           ? 'active' : ''}">프로필 설정</a>
          <a href="transfer-history.html" class="sidebar-subitem ${path === 'transfer-history.html' ? 'active' : ''}">캐릭터 이전 내역</a>
        </div>
      </div>
      <a href="notifications.html" class="sidebar-item sidebar-login ${path === 'notifications.html' ? 'active' : ''}" style="justify-content:space-between;">
        알림<span class="sidebar-notif-badge" id="sidebarNotifBadge" style="display:none">0</span>
      </a>
    </nav>

    <div class="sidebar-divider"></div>

    <nav class="sidebar-menu">
      <a href="#" class="sidebar-item">문의</a>
      <a href="#" class="sidebar-item">버그리포트</a>
    </nav>
  `;

  // 종족 관련 페이지면 종족 아코디언 자동 열기
  if (path === 'species.html' || path === 'species-list.html') {
    document.getElementById('bodySpecies').classList.add('open');
    document.getElementById('arrSpecies').style.transform = 'rotate(180deg)';
  }


  // 내 정보 하위 페이지면 아코디언 자동 열기
  if (path === 'profile.html' || path === 'transfer-history.html') {
    document.getElementById('bodyMyInfo').classList.add('open');
    document.getElementById('arrMyInfo').style.transform = 'rotate(180deg)';
  }

  loadSpeciesSidebar();
  updateSidebarLogin();
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

  // 사이드바 링크 클릭 시 닫기 (모바일)
  const sidebar = document.getElementById('sidebar');
  if (sidebar) {
    sidebar.querySelectorAll('a, button').forEach(el => {
      el.addEventListener('click', () => {
        if (window.innerWidth <= 767) closeSidebar();
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

async function loadSpeciesSidebar() {
  const body = document.getElementById('bodySpecies');
  if (!body) return;

  const { data, error } = await sb.from('species').select('id, name').order('name');

  const allLink = `<a href="species-list.html" class="sidebar-subitem sidebar-subitem--all">전체보기</a>`;

  if (error || !data || data.length === 0) {
    const dummy = ['드래곤','엘프','요정','늑대인간','슬라임','골렘'];
    body.innerHTML = allLink + dummy.map(name =>
      `<a href="species-list.html" class="sidebar-subitem" style="opacity:0.45;">${name}</a>`
    ).join('');
  } else {
    const q    = new URLSearchParams(window.location.search);
    const curr = q.get('id');
    body.innerHTML = allLink + data.map(s =>
      `<a href="species.html?id=${s.id}" class="sidebar-subitem ${curr === String(s.id) ? 'active' : ''}">${s.name}</a>`
    ).join('');
  }

  // 종족 목록 로드 후 새로 생긴 링크에도 닫기 이벤트 등록
  body.querySelectorAll('a').forEach(el => {
    el.addEventListener('click', () => {
      if (window.innerWidth <= 767) closeSidebar();
    });
  });
}

async function updateSidebarLogin() {
  const user = await getUser();

  if (user) {
    document.querySelectorAll('.sidebar-login').forEach(el => el.classList.remove('sidebar-login'));
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

document.addEventListener('DOMContentLoaded', initSidebar);
