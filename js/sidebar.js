async function initSidebar() {
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;

  const path = window.location.pathname.split('/').pop();

  sidebar.innerHTML = `
    <div class="sidebar-user-block" id="sidebarUserBlock"></div>

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
      <a href="my-designs.html"    class="sidebar-item sidebar-login ${path === 'my-designs.html'    ? 'active' : ''}">내 디자인</a>
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
      <a href="species-apply.html" class="sidebar-item ${path === 'species-apply.html' || path === 'species-apply-write.html' || path === 'species-apply-detail.html' ? 'active' : ''}" style="justify-content:space-between;">✨종족주 신청✨<span class="sidebar-notif-badge" id="sidebarApplyBadge" style="display:none">0</span></a>
      <a href="inquiry.html"    class="sidebar-item ${path === 'inquiry.html' || path === 'inquiry-write.html' || path === 'inquiry-detail.html' ? 'active' : ''}" style="justify-content:space-between;">문의<span class="sidebar-notif-badge" id="sidebarInquiryBadge" style="display:none">0</span></a>
      <a href="bug-report.html" class="sidebar-item ${path === 'bug-report.html' || path === 'bug-report-write.html' || path === 'bug-report-detail.html' ? 'active' : ''}" style="justify-content:space-between;">버그리포트<span class="sidebar-notif-badge" id="sidebarBugBadge" style="display:none">0</span></a>
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
      if (window.innerWidth <= 767 && !el.classList.contains('sidebar-accordion-btn')) {
        closeSidebar();
      }
    });
  });
}

async function updateSidebarLogin() {
  const user = await getUser();
  const block = document.getElementById('sidebarUserBlock');

  if (user) {
    document.querySelectorAll('.sidebar-login').forEach(el => el.classList.remove('sidebar-login'));

    if (block) {
      const nickname = user.user_metadata?.display_name || user.user_metadata?.nickname || '유저';
      const admin = user.user_metadata?.role === 'admin';
      const TESTERS = ['Moulow', 'moulow', 'Sawol'];
      const isTester = TESTERS.includes(nickname);
      const roleIsSpeciesOwner = user.user_metadata?.role === 'species_owner';
      const { data: ownedSpecies } = await sb.from('species').select('id')
        .or(`owner_user_id.eq.${user.id},and(owner_user_id.is.null,owner_nickname.eq.${nickname})`).limit(1);
      const isSpeciesOwner = roleIsSpeciesOwner || (ownedSpecies && ownedSpecies.length > 0);

      const badges = [];
      if (admin)          badges.push(`<a href="admin.html" class="badge-admin">관리자</a>`);
      if (isTester)       badges.push(`<span style="font-size:10px;padding:3px 8px;background:#dcfce7;color:#166534;border-radius:4px;font-weight:700;">테스터</span>`);
      if (isSpeciesOwner) badges.push(`<span class="badge-role">종족주</span>`);
      if (!admin && !isTester && !isSpeciesOwner) badges.push(`<span class="badge-user">일반유저</span>`);

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
  if (user?.user_metadata?.role !== 'admin') return;

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
