window.isAdmin        = (role) => role === 'admin';
window.isStaff        = (role) => role === 'staff';
window.isAdminOrStaff = (role) => role === 'admin' || role === 'staff';

const SUPABASE_URL = 'https://tnvkfcqphdxdyvswbkfe.supabase.co';
const SUPABASE_KEY = 'sb_publishable_iaH_vCaDJfekUiZ85_JO7w_T_iDGNfg';

const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

// 닉네임 → 가짜 이메일 변환
function toEmail(nickname) {
  return `${nickname}@dogam.com`;
}

// 회원가입
async function signUp(nickname, password) {
  const { data, error } = await sb.auth.signUp({
    email: toEmail(nickname),
    password,
    options: { data: { nickname } }
  });
  return { data, error };
}

// 로그인
async function signIn(nickname, password) {
  const { data, error } = await sb.auth.signInWithPassword({
    email: toEmail(nickname),
    password,
  });
  return { data, error };
}

// 로그아웃
async function signOut() {
  await sb.auth.signOut();
  window.location.href = 'index.html';
}

// 현재 로그인된 유저
async function getUser() {
  const { data: { user } } = await sb.auth.getUser();
  return user;
}

// 관리자/스태프 여부
async function isAdmin() {
  const user = await getUser();
  return isAdminOrStaff(user?.user_metadata?.role);
}

// 프로필 업데이트 (소개글 등)
async function updateProfile(data) {
  const { error } = await sb.auth.updateUser({ data });
  return { error };
}

// 비밀번호 변경
async function updatePassword(newPassword) {
  const { error } = await sb.auth.updateUser({ password: newPassword });
  return { error };
}

// 계정 탈퇴 (로그아웃 처리 - 실제 삭제는 서버사이드 필요)
async function deleteAccount() {
  await sb.auth.signOut();
  window.location.href = 'index.html';
}

// 내 캐릭터 조회 — owner_user_id 기준만, 오프사이트 제외
async function getMyCharacters(userId, nickname) {
  if (!userId) return { data: [], error: null };
  const { data, error } = await sb
    .from('characters').select('*')
    .eq('owner_user_id', userId)
    .neq('owner_is_offsite', true)
    .order('created_at', { ascending: false });
  return { data, error };
}

// 내 종족 조회 (UUID 우선, 표시용 nickname fallback)
async function getMySpecies(userId, nickname) {
  if (userId) {
    const { data: byId, error } = await sb
      .from('species').select('*')
      .eq('owner_user_id', userId)
      .order('created_at', { ascending: false });
    if (!error && byId?.length) return { data: byId, error: null };
  }
  if (!nickname) return { data: [], error: null };
  const { data, error } = await sb
    .from('species').select('*')
    .eq('owner_nickname', nickname)
    .is('owner_user_id', null)
    .order('created_at', { ascending: false });
  return { data, error };
}

// 캐릭터 이전 로그 기록
async function logTransfer({ character_name, species_name, from_nickname, to_nickname, method }) {
  const { error } = await sb.from('character_transfers').insert({
    character_name,
    species_name,
    from_nickname,
    to_nickname,
    method,
  });
  return { error };
}

// 이전 내역 조회 — nickname은 문자열 또는 배열 모두 허용
async function getTransferHistory(nicknames) {
  const nicks = [...new Set([].concat(nicknames).filter(Boolean))];
  const orParts = nicks.flatMap(n => [`from_nickname.eq.${n}`, `to_nickname.eq.${n}`]).join(',');
  const { data, error } = await sb
    .from('character_transfers')
    .select('*')
    .or(orParts)
    .order('created_at', { ascending: false });
  return { data, error };
}

// 헤더 상태 업데이트
async function updateHeader() {
  const user = await getUser();
  const admin = user?.user_metadata?.role === 'admin';
  const staff = user?.user_metadata?.role === 'staff';
  const loginBtn = document.querySelector('.btn-login');

  if (user) {
    const nickname = user.user_metadata?.display_name || user.user_metadata?.nickname || '유저';

    const TESTERS = ['Moulow', 'moulow', 'Sawol'];
    const roleIsSpeciesOwner = user.user_metadata?.role === 'species_owner';
    const { data: spById }   = await sb.from('species').select('id').eq('owner_user_id', user.id).limit(1);
    const { data: spByNick } = spById?.length ? { data: null } :
      await sb.from('species').select('id').eq('owner_nickname', nickname).is('owner_user_id', null).limit(1);
    const isSpeciesOwner = roleIsSpeciesOwner || !!(spById?.length || spByNick?.length);
    const isTester = TESTERS.includes(nickname);

    if (loginBtn) {
      loginBtn.textContent = nickname;
      loginBtn.href = 'profile.html';
      loginBtn.classList.remove('btn-login');
      loginBtn.classList.add('btn-username');

      // 뱃지: 관리자 → 테스터 → 종족주 순으로 닉네임 앞에
      const headerBadges = [];
      if (admin)                                        headerBadges.push(`<a href="admin.html" class="badge-admin">관리자</a>`);
      if (staff)                                        headerBadges.push(`<a href="admin.html" class="badge-staff">스태프</a>`);
      if (isTester && !staff)                           headerBadges.push(`<span style="font-size:10px; padding:3px 8px; background:#dcfce7; color:#166534; border-radius:4px; font-weight:700; display:inline-block; margin-right:4px;">테스터</span>`);
      if (isSpeciesOwner)                               headerBadges.push(`<span class="badge-role">종족주</span>`);
      if (!admin && !staff && !isTester && !isSpeciesOwner) headerBadges.push(`<span class="badge-user">일반유저</span>`);
      if (headerBadges.length) {
        loginBtn.insertAdjacentHTML('beforebegin', headerBadges.join(''));
      }

      // 로그아웃은 닉네임 뒤에
      loginBtn.insertAdjacentHTML('afterend',
        `<button class="btn-logout" onclick="signOut()">로그아웃</button>`
      );
    }
  }
}

document.addEventListener('DOMContentLoaded', updateHeader);
