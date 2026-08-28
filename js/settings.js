// MY > 설정 페이지
// user_settings 조회/저장은 js/utils.js의 getUserSettings()/updateUserSettings() 공용 헬퍼를 사용한다.
// (상점 js/shop.js도 동일한 헬퍼로 같은 DB 값을 공유한다 — 토글 동기화)

let _settingsUserId = null;

async function initPage() {
  try {
    const user = await getUser();
    if (!user) { window.location.href = 'login.html'; return; }
    _settingsUserId = user.id;

    const settings = await getUserSettings(user.id);

    const toggle = document.getElementById('hideSensitiveToggle');
    toggle.checked = settings.hide_sensitive_content;
    toggle.addEventListener('change', async () => {
      const next = toggle.checked;
      toggle.disabled = true;
      const { error } = await updateUserSettings(_settingsUserId, { hide_sensitive_content: next });
      toggle.disabled = false;
      if (error) {
        toggle.checked = !next; // 실패 시 되돌리기
        alert('설정 저장에 실패했어요. 다시 시도해주세요.');
      }
    });

    document.getElementById('pageLoading').style.display = 'none';
    document.getElementById('pageContent').style.display = 'block';
  } catch (e) {
    console.error('[settings] initPage 오류:', e);
    document.getElementById('pageLoading').textContent = '불러오기 실패. 새로고침 해주세요.';
  }
}

initPage();
