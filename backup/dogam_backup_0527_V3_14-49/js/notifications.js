async function initNotifications() {
  const user = await getUser();
  if (!user) return;
  const myNick = user.user_metadata?.display_name || user.user_metadata?.nickname;
  if (!myNick) return;

  refreshNotifCount(myNick);

  sb.channel(`notif_${myNick.replace(/\W/g, '_')}`)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'notifications',
      filter: `user_nickname=eq.${myNick}`
    }, () => refreshNotifCount(myNick))
    .subscribe();
}

function insertNotifBell() {
  const nav = document.querySelector('.header-nav');
  if (!nav || document.getElementById('notifBellWrap')) return;

  const wrap = document.createElement('div');
  wrap.className = 'notif-bell-wrap';
  wrap.id = 'notifBellWrap';
  wrap.innerHTML = `
    <button class="notif-bell-btn" id="notifBellBtn" onclick="toggleNotifPanel(event)">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
      </svg>
      <span class="notif-badge" id="notifBadge" style="display:none">0</span>
    </button>
    <div class="notif-panel" id="notifPanel" style="display:none">
      <div class="notif-panel-header">
        <span class="notif-panel-title">알림</span>
        <button class="notif-read-all-btn" onclick="markAllRead()">모두 읽음</button>
      </div>
      <div id="notifPanelList" class="notif-panel-list">
        <p class="notif-empty">불러오는 중...</p>
      </div>
    </div>
  `;
  nav.prepend(wrap);

  document.addEventListener('click', (e) => {
    const panel   = document.getElementById('notifPanel');
    const bellWrap = document.getElementById('notifBellWrap');
    if (panel && bellWrap && !bellWrap.contains(e.target)) {
      panel.style.display = 'none';
    }
  });
}

async function refreshNotifCount(myNick) {
  const { count } = await sb.from('notifications')
    .select('*', { count: 'exact', head: true })
    .eq('user_nickname', myNick)
    .eq('is_read', false);

  const n = count || 0;
  const badge        = document.getElementById('notifBadge');
  const sidebarBadge = document.getElementById('sidebarNotifBadge');

  if (badge) {
    badge.textContent  = n > 99 ? '99+' : n;
    badge.style.display = n > 0 ? 'flex' : 'none';
  }
  if (sidebarBadge) {
    sidebarBadge.textContent  = n > 99 ? '99+' : n;
    sidebarBadge.style.display = n > 0 ? 'inline-flex' : 'none';
  }
}

async function toggleNotifPanel(e) {
  if (e) e.stopPropagation();
  const panel = document.getElementById('notifPanel');
  if (!panel) return;
  const isOpen = panel.style.display === 'block';
  panel.style.display = isOpen ? 'none' : 'block';
  if (!isOpen) {
    const user = await getUser();
    const myNick = user?.user_metadata?.display_name || user?.user_metadata?.nickname;
    if (myNick) loadNotifList(myNick);
  }
}

function openNotifFromSidebar() {
  const panel = document.getElementById('notifPanel');
  if (!panel) return;
  panel.style.display = 'block';
  getUser().then(user => {
    const myNick = user?.user_metadata?.display_name || user?.user_metadata?.nickname;
    if (myNick) loadNotifList(myNick);
  });
}

async function loadNotifList(myNick) {
  const { data } = await sb.from('notifications')
    .select('*')
    .eq('user_nickname', myNick)
    .order('created_at', { ascending: false })
    .limit(30);

  const listEl = document.getElementById('notifPanelList');
  if (!listEl) return;

  if (!data || data.length === 0) {
    listEl.innerHTML = '<p class="notif-empty">알림이 없어요</p>';
    return;
  }

  listEl.innerHTML = data.map(n => `
    <a class="notif-item${n.is_read ? '' : ' notif-item--unread'}"
       href="${n.link || '#'}"
       onclick="markRead('${n.id}'); return true;">
      <span class="notif-msg">${escapeNotif(n.message)}</span>
      <span class="notif-time">${timeAgoNotif(n.created_at)}</span>
    </a>
  `).join('');
}

async function markRead(id) {
  await sb.from('notifications').update({ is_read: true }).eq('id', id);
  const user = await getUser();
  const myNick = user?.user_metadata?.nickname;
  if (myNick) refreshNotifCount(myNick);
}

async function markAllRead() {
  const user = await getUser();
  const myNick = user?.user_metadata?.display_name || user?.user_metadata?.nickname;
  if (!myNick) return;
  await sb.from('notifications').update({ is_read: true })
    .eq('user_nickname', myNick).eq('is_read', false);
  refreshNotifCount(myNick);
  const listEl = document.getElementById('notifPanelList');
  if (listEl) listEl.innerHTML = '<p class="notif-empty">알림이 없어요</p>';
}

function timeAgoNotif(dateStr) {
  const m = Math.floor((Date.now() - new Date(dateStr)) / 60000);
  if (m < 1)  return '방금 전';
  if (m < 60) return `${m}분 전`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}시간 전`;
  return `${Math.floor(h / 24)}일 전`;
}

function escapeNotif(str) {
  return String(str)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

document.addEventListener('DOMContentLoaded', () => {
  insertNotifBell();   // 동기 실행 — auth가 닉네임 삽입하기 전에 먼저 위치 확보
  initNotifications(); // async — 로그인 확인 후 뱃지 숫자 채움
});
