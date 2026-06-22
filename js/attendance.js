const STAMP_IMG   = '../images/attendance_stamp.png';
const BONUS_STEPS = [7, 14, 21, 28];

let _user          = null;
let _year          = 0;
let _month         = 0;
let _monthKey      = '';
let _attendedDates = new Set();
let _wallet        = null;
let _claimedSteps  = new Set();

// ── 초기화 ──────────────────────────────────────────────
async function initPage() {
  try {
    _user = await getUser();
    if (!_user) { window.location.href = 'login.html'; return; }

    await loadData();
    renderAll();

    document.getElementById('pageLoading').style.display = 'none';
    document.getElementById('pageContent').style.display = '';
  } catch (e) {
    console.error('[attendance] initPage 오류:', e);
    document.getElementById('pageLoading').textContent = '불러오기 실패. 새로고침 해주세요.';
  }
}

async function loadData() {
  const now  = new Date();
  _year      = now.getFullYear();
  _month     = now.getMonth();
  _monthKey  = `${_year}-${pad(_month + 1)}`;

  const firstDay = `${_monthKey}-01`;
  const lastDay  = `${_monthKey}-${new Date(_year, _month + 1, 0).getDate()}`;

  const [logsRes, walletRes, rewardsRes] = await Promise.all([
    sb.from('attendance_logs')
      .select('attendance_date')
      .eq('user_id', _user.id)
      .gte('attendance_date', firstDay)
      .lte('attendance_date', lastDay),
    getMyWallet(_user.id),
    sb.from('attendance_rewards')
      .select('reward_step')
      .eq('user_id', _user.id)
      .eq('month_key', _monthKey),
  ]);

  _attendedDates = new Set((logsRes.data    || []).map(l => l.attendance_date));
  _wallet        = walletRes.data;
  _claimedSteps  = new Set((rewardsRes.data || []).map(r => r.reward_step));
}

// ── 전체 렌더 ────────────────────────────────────────────
function renderAll() {
  renderSummary();
  renderCheckinArea();
  renderCalendar();
  renderBonusGuide();
}

// ── 요약 영역 ────────────────────────────────────────────
function renderSummary() {
  const count      = _attendedDates.size;
  const nextBonus  = BONUS_STEPS.find(s => s > count);
  const remaining  = nextBonus ? nextBonus - count : 0;

  document.getElementById('summaryCount').textContent = count;

  const nextEl   = document.getElementById('summaryNextBonus');
  const unitEl   = document.getElementById('summaryNextBonusUnit');
  if (nextBonus) {
    nextEl.textContent = remaining;
    unitEl.textContent = '회 남음';
  } else {
    nextEl.textContent = '완주!';
    unitEl.textContent = '';
  }
}

// ── 출석 버튼 영역 ───────────────────────────────────────
function renderCheckinArea() {
  const attended = _attendedDates.has(todayStr());
  const btn  = document.getElementById('checkinBtn');
  const done = document.getElementById('checkinDone');

  if (attended) {
    btn.style.display  = 'none';
    done.style.display = '';
  } else {
    btn.style.display  = '';
    done.style.display = 'none';
    btn.disabled       = false;
    btn.textContent    = '출석 체크';
  }
}

// ── 달력 ─────────────────────────────────────────────────
function renderCalendar() {
  const monthNames = ['1월','2월','3월','4월','5월','6월','7월','8월','9월','10월','11월','12월'];
  document.getElementById('calMonthTitle').textContent = `${_year}년 ${monthNames[_month]}`;

  const daysInMonth  = new Date(_year, _month + 1, 0).getDate();
  const firstWeekday = new Date(_year, _month, 1).getDay();
  const today        = todayStr();
  const grid         = document.getElementById('calGrid');
  grid.innerHTML     = '';

  // 앞 빈 칸
  for (let i = 0; i < firstWeekday; i++) {
    const el = document.createElement('div');
    el.className = 'attn-day attn-day--empty';
    grid.appendChild(el);
  }

  for (let d = 1; d <= daysInMonth; d++) {
    const dateStr  = `${_year}-${pad(_month + 1)}-${pad(d)}`;
    const isToday  = dateStr === today;
    const attended = _attendedDates.has(dateStr);

    const cell = document.createElement('div');
    cell.className = 'attn-day'
      + (isToday  ? ' attn-day--today'    : '')
      + (attended ? ' attn-day--attended' : '');

    const num = document.createElement('span');
    num.className   = 'attn-day-num';
    num.textContent = d;
    cell.appendChild(num);

    if (attended) {
      const stamp = document.createElement('div');
      stamp.className = 'attendance-stamp';
      stamp.innerHTML = `<img src="${STAMP_IMG}" alt="출석">`;
      cell.appendChild(stamp);
    }

    grid.appendChild(cell);
  }
}

// ── 보너스 안내 ──────────────────────────────────────────
function renderBonusGuide() {
  const count = _attendedDates.size;

  BONUS_STEPS.forEach((step, i) => {
    const stepEl = document.getElementById(`bonusStep${step}`);
    if (!stepEl) return;

    // 달성한 구간만 활성화 (count >= step)
    const achieved = count >= step;
    stepEl.classList.toggle('attn-bonus-step--done', achieved);
    stepEl.classList.remove('attn-bonus-step--current');

    // 연결선: 다음 구간이 달성된 경우 채우기
    const lineEl = document.getElementById(`bonusLine${BONUS_STEPS[i - 1]}`);
    if (lineEl) lineEl.classList.toggle('attn-bonus-line--done', count >= step);
  });
}

// ── 출석 체크인 ──────────────────────────────────────────
async function checkIn() {
  const btn = document.getElementById('checkinBtn');
  btn.disabled    = true;
  btn.textContent = '처리 중...';
  hideResultMsg();

  try {
    const { data, error } = await sb.rpc('record_attendance');

    if (error || !data?.success) {
      showResultMsg(
        data?.error === 'ALREADY_ATTENDED'
          ? '이미 오늘 출석하셨습니다.'
          : '출석 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
        'error'
      );
      return;
    }

    // 상태 갱신
    _attendedDates.add(todayStr());
    if (data.bonus_step) _claimedSteps.add(data.bonus_step);
    if (data.new_research != null) {
      _wallet = { ...(_wallet || {}), research_records: data.new_research, keys: data.new_keys };
    }

    // 상단바 재화 즉시 반영 (auth.js의 공용 함수)
    if (typeof updateHeaderCurrencyDisplay === 'function') {
      updateHeaderCurrencyDisplay({ research_records: data.new_research, keys: data.new_keys });
    }

    renderAll();

    let msg = `출석 완료! 연구기록 +${data.research_earned}`;
    if (data.keys_earned > 0) msg += `, 열쇠 +${data.keys_earned}`;
    if (data.bonus_step  > 0) msg += ` · ${data.bonus_step}회 달성 보너스 지급!`;
    showResultMsg(msg, 'success');

  } catch (e) {
    console.error('[attendance] checkIn 오류:', e);
    showResultMsg('출석 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.', 'error');
  } finally {
    // 출석이 완료되지 않은 상태면 버튼 항상 복원
    if (!_attendedDates.has(todayStr())) {
      btn.disabled    = false;
      btn.textContent = '출석 체크';
    }
  }
}

// ── 유틸 ─────────────────────────────────────────────────
function pad(n) { return String(n).padStart(2, '0'); }

function todayStr() {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function showResultMsg(text, type) {
  const el = document.getElementById('resultMsg');
  if (!el) return;
  el.textContent = text;
  el.className   = `attn-result-msg attn-result-msg--${type}`;
  el.style.display = '';
}

function hideResultMsg() {
  const el = document.getElementById('resultMsg');
  if (el) el.style.display = 'none';
}

initPage();
