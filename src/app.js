import {
  GRADE_CONFIG,
  TOTAL_QUESTIONS_PER_GRADE,
  getGrade,
  getRandomQuestions,
  getQuestionsForGrade,
} from './data.js';

const STORAGE_KEY = 'kanji-kombat-player-v1';
const ROOM_KEY = 'kanji-kombat-room-v1';
const app = document.querySelector('#view-root');
const modalRoot = document.querySelector('#modal-root');
const toastRoot = document.querySelector('#toast-root');

const PAGE_TITLES = {
  dashboard: 'アリーナへようこそ',
  battle: '対戦アリーナ',
  practice: 'トレーニングデッキ',
  rankings: 'シーズンランキング',
};

const DEFAULT_STATE = {
  view: 'dashboard',
  selectedGrade: '5',
  selectedMode: 'ranked',
  notifications: 2,
  profile: {
    name: 'HINATA',
    level: 12,
    xp: 2830,
    rating: 1248,
    streak: 7,
    wins: 38,
    losses: 12,
    avatar: 'H',
  },
  stats: {
    matches: 50,
    answered: 824,
    correct: 709,
    bestStreak: 7,
    practiceAnswers: 126,
  },
  recentMatches: [
    { opponent: 'MIZUKI', grade: '準2', score: '4 - 2', result: 'WIN', time: '8分前', accent: 'pink' },
    { opponent: 'REN', grade: '5', score: '3 - 3', result: 'DRAW', time: '1時間前', accent: 'violet' },
    { opponent: 'AOI', grade: '3', score: '2 - 4', result: 'LOSS', time: '昨日', accent: 'orange' },
  ],
};

let state = loadState();
let match = null;
let practiceSession = null;
let roomSession = loadRoomSession();
let matchTimers = { clock: null, opponent: null, countdown: null, search: null };
let toastTimer = null;

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function loadState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
    if (!saved) return clone(DEFAULT_STATE);
    return {
      ...clone(DEFAULT_STATE),
      ...saved,
      profile: { ...clone(DEFAULT_STATE).profile, ...(saved.profile || {}) },
      stats: { ...clone(DEFAULT_STATE).stats, ...(saved.stats || {}) },
      recentMatches: Array.isArray(saved.recentMatches) ? saved.recentMatches : clone(DEFAULT_STATE.recentMatches),
    };
  } catch {
    return clone(DEFAULT_STATE);
  }
}

function saveState() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // The game still works in private browsing even when storage is unavailable.
  }
}

function loadRoomSession() {
  try {
    return JSON.parse(localStorage.getItem(ROOM_KEY) || 'null');
  } catch {
    return null;
  }
}

function saveRoomSession() {
  try {
    if (roomSession) localStorage.setItem(ROOM_KEY, JSON.stringify(roomSession));
    else localStorage.removeItem(ROOM_KEY);
  } catch {
    // Optional enhancement only.
  }
}

function escapeHtml(value = '') {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function formatNumber(value) {
  return new Intl.NumberFormat('ja-JP').format(Number(value) || 0);
}

function formatRating(value) {
  return new Intl.NumberFormat('ja-JP').format(Number(value) || 0);
}

function normalizeReading(value = '') {
  return String(value)
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[ァ-ヶ]/g, (character) => String.fromCharCode(character.charCodeAt(0) - 0x60))
    .replace(/[\s　]/g, '')
    .replace(/・/g, '')
    .trim();
}

function randomItem(items) {
  return items[Math.floor(Math.random() * items.length)];
}

function createRoomCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let result = '';
  for (let index = 0; index < 6; index += 1) result += letters[Math.floor(Math.random() * letters.length)];
  return result.slice(0, 3) + '-' + result.slice(3);
}

function showToast(message, tone = 'default') {
  clearTimeout(toastTimer);
  toastRoot.innerHTML = `<div class="toast toast-${tone}"><span class="toast-mark">${tone === 'success' ? '✓' : tone === 'error' ? '!' : '✦'}</span><span>${escapeHtml(message)}</span></div>`;
  requestAnimationFrame(() => toastRoot.querySelector('.toast')?.classList.add('is-visible'));
  toastTimer = setTimeout(() => {
    toastRoot.querySelector('.toast')?.classList.remove('is-visible');
  }, 3200);
}

function setView(view) {
  if (!PAGE_TITLES[view]) return;
  state.view = view;
  saveState();
  render();
}

function setGrade(gradeKey) {
  if (!GRADE_CONFIG.some((grade) => grade.key === String(gradeKey))) return;
  state.selectedGrade = String(gradeKey);
  saveState();
  render();
}

function setMode(mode) {
  if (!['ranked', 'quick', 'friend'].includes(mode)) return;
  state.selectedMode = mode;
  saveState();
  render();
}

function updateChrome() {
  document.querySelectorAll('.nav-item[data-view]').forEach((item) => {
    item.classList.toggle('is-active', item.dataset.view === state.view);
  });
  const title = document.querySelector('#topbar-page-title');
  if (title) title.textContent = PAGE_TITLES[state.view] || PAGE_TITLES.dashboard;
  const name = document.querySelector('#sidebar-player-name');
  if (name) name.textContent = state.profile.name;
  const xpIntoLevel = state.profile.xp % 1000;
  const xpBar = document.querySelector('#sidebar-xp-bar');
  const xpLabel = document.querySelector('#sidebar-xp-label');
  if (xpBar) xpBar.style.width = `${Math.max(8, Math.min(98, (xpIntoLevel / 1000) * 100))}%`;
  if (xpLabel) xpLabel.textContent = `${formatNumber(1000 - xpIntoLevel)} XP`;
  const notificationBadge = document.querySelector('.notification-badge');
  if (notificationBadge) {
    notificationBadge.textContent = state.notifications;
    notificationBadge.hidden = state.notifications === 0;
  }
}

function gradePill(gradeKey, extraClass = '') {
  const grade = getGrade(gradeKey);
  return `<span class="grade-pill ${extraClass} grade-${grade.color}"><span class="grade-pill-dot"></span>${grade.label}</span>`;
}

function renderAvatar(name, color = 'cyan', size = '') {
  const initial = escapeHtml((name || '?').slice(0, 1));
  return `<div class="avatar avatar-${color} ${size ? `avatar-${size}` : ''}"><span>${initial}</span><i class="online-indicator"></i></div>`;
}

function renderGradeTile(grade, compact = false) {
  const selected = String(state.selectedGrade) === grade.key;
  const questions = getQuestionsForGrade(grade.key).length;
  return `
    <button class="grade-tile grade-${grade.color} ${selected ? 'is-selected' : ''} ${compact ? 'is-compact' : ''}" data-action="select-grade" data-grade="${grade.key}" style="--grade-accent:${grade.accent}">
      <span class="grade-tile-glow"></span>
      <span class="grade-tile-top"><b>${grade.label}</b><i class="tile-check">${selected ? '✓' : ''}</i></span>
      <span class="grade-tile-difficulty">${escapeHtml(grade.difficulty)}</span>
      <span class="grade-tile-detail">${escapeHtml(grade.detail)}</span>
      <span class="grade-tile-foot"><b>${questions}問</b><span>読みプール</span></span>
    </button>`;
}

function renderDashboard() {
  const profile = state.profile;
  const selectedGrade = getGrade(state.selectedGrade);
  const accuracy = state.stats.answered ? Math.round((state.stats.correct / state.stats.answered) * 100) : 0;
  const nextRankXp = 1000 - (profile.xp % 1000);
  return `
    <div class="page page-dashboard">
      <section class="dashboard-hero">
        <div class="hero-copy">
          <div class="eyebrow"><span class="eyebrow-mark"></span> PLAYER DASHBOARD <span class="eyebrow-live">LIVE</span></div>
          <h1>読みの速さで、<br><em>勝負を決めろ。</em></h1>
          <p>漢検の級別難易度で鍛える、読みだけのオンライン漢字バトル。<br>一問の判断が、あなたのレートを動かす。</p>
          <div class="hero-actions">
            <button class="button button-primary" data-action="start-match"><span class="button-icon">⚔</span> 対戦を探す <span class="button-arrow">→</span></button>
            <button class="button button-ghost" data-action="open-practice"><span class="button-icon">◎</span> ひとりで練習</button>
          </div>
          <div class="hero-trust"><span class="avatar-stack"><i class="avatar avatar-tiny avatar-yellow">K</i><i class="avatar avatar-tiny avatar-pink">M</i><i class="avatar avatar-tiny avatar-blue">R</i></span><span><b>1,284</b>人が今プレイ中</span><span class="trust-divider"></span><span>サーバー遅延 <b class="green-text">32ms</b></span></div>
        </div>
        <div class="hero-arena" aria-label="対戦プレビュー">
          <div class="arena-scanline"></div>
          <div class="hero-orbit orbit-one"></div><div class="hero-orbit orbit-two"></div>
          <div class="hero-kanji kanji-back">読</div>
          <div class="hero-kanji kanji-front">漢</div>
          <div class="hero-vs-badge"><span>LIVE</span><b>VS</b><small>READ ONLY</small></div>
          <div class="hero-player-tag tag-left"><i></i> YOU <b>12</b></div>
          <div class="hero-player-tag tag-right">KAI <b>11</b> <i></i></div>
          <div class="hero-particle particle-a"></div><div class="hero-particle particle-b"></div><div class="hero-particle particle-c"></div>
        </div>
      </section>

      <section class="stat-strip">
        <div class="stat-item"><span class="stat-label">CURRENT RATING <i class="tiny-help">?</i></span><strong>${formatRating(profile.rating)}</strong><span class="stat-change positive">↑ 42 <small>今週</small></span></div>
        <div class="stat-item"><span class="stat-label">WIN RATE</span><strong>${Math.round((profile.wins / Math.max(1, profile.wins + profile.losses)) * 100)}<small>%</small></strong><span class="stat-note">TOP 18%</span></div>
        <div class="stat-item"><span class="stat-label">READ STREAK</span><strong class="streak-number">${profile.streak}<small>連勝</small></strong><span class="stat-change orange-text">✦ BEST ${state.stats.bestStreak}</span></div>
        <div class="stat-item"><span class="stat-label">ACCURACY</span><strong>${accuracy}<small>%</small></strong><span class="stat-note">${formatNumber(state.stats.answered)}問回答</span></div>
        <div class="stat-item stat-xp"><span class="stat-label">SEASON XP</span><strong>${formatNumber(profile.xp)}</strong><div class="mini-xp"><span style="width:${Math.max(8, (profile.xp % 1000) / 10)}%"></span></div><span class="stat-note">NEXT LEVEL <b>${formatNumber(nextRankXp)} XP</b></span></div>
      </section>

      <section class="section-block grade-section">
        <div class="section-heading"><div><div class="eyebrow subtle">CHOOSE YOUR LEVEL</div><h2>漢検ランクを選ぶ</h2></div><button class="text-button" data-view="battle">対戦設定を開く <span>→</span></button></div>
        <div class="grade-grid">${GRADE_CONFIG.map((grade) => renderGradeTile(grade)).join('')}</div>
      </section>

      <section class="dashboard-lower-grid">
        <div class="panel live-match-panel">
          <div class="panel-heading"><div><div class="eyebrow subtle">MATCHMAKING</div><h3>今すぐ対戦する</h3></div><span class="panel-live"><i></i> LIVE</span></div>
          <div class="match-preview">
            <div class="match-user"><div class="match-avatar-wrap">${renderAvatar(profile.name, 'cyan', 'lg')}<span class="level-chip">LV ${profile.level}</span></div><strong>${escapeHtml(profile.name)}</strong><span>${formatRating(profile.rating)} RATING</span></div>
            <div class="match-versus"><span class="versus-line"></span><b>VS</b><span class="versus-line"></span><small>BEST OF 5</small></div>
            <div class="match-user opponent"><div class="match-avatar-wrap">${renderAvatar('KAI', 'orange', 'lg')}<span class="level-chip dark">LV 11</span></div><strong>KAI</strong><span>1,231 RATING</span></div>
          </div>
          <div class="match-footer"><span>${gradePill(state.selectedGrade)} <b>${selectedGrade.label}を選択中</b></span><button class="button button-small button-primary" data-action="start-match">クイックマッチ <span>→</span></button></div>
        </div>
        <div class="panel missions-panel">
          <div class="panel-heading"><div><div class="eyebrow subtle">DAILY MISSION</div><h3>今日のチャレンジ</h3></div><span class="mission-count">2 / 3</span></div>
          <div class="mission-list">
            <div class="mission-row is-done"><span class="mission-icon">✓</span><div><b>3問連続で正解する</b><small>+80 XP</small></div><span class="mission-check">DONE</span></div>
            <div class="mission-row"><span class="mission-icon target">◎</span><div><b>対戦で2勝する</b><small>+120 XP</small></div><span class="mission-progress">1 / 2</span></div>
            <div class="mission-row"><span class="mission-icon target">◎</span><div><b>新しい級に挑戦する</b><small>+100 XP</small></div><span class="mission-progress">0 / 1</span></div>
          </div>
        </div>
      </section>

      <section class="section-block recent-section">
        <div class="section-heading"><div><div class="eyebrow subtle">MATCH HISTORY</div><h2>最近の対戦</h2></div><button class="text-button" data-action="show-history">すべて見る <span>→</span></button></div>
        <div class="history-table">
          <div class="history-head"><span>対戦相手</span><span>級</span><span>スコア</span><span>結果</span><span>日時</span><span></span></div>
          ${state.recentMatches.map((item) => `<div class="history-row"><div class="history-opponent">${renderAvatar(item.opponent, item.accent, 'xs')}<div><b>${escapeHtml(item.opponent)}</b><small>${item.result === 'WIN' ? '読みの達人' : item.result === 'DRAW' ? '互角の一戦' : '強敵'}</small></div></div><span>${gradePill(item.grade)}</span><strong class="history-score">${item.score}</strong><span class="result-badge result-${item.result.toLowerCase()}">${item.result === 'WIN' ? 'WIN' : item.result === 'LOSS' ? 'LOSS' : 'DRAW'}</span><span class="history-time">${item.time}</span><button class="row-more" aria-label="詳細">•••</button></div>`).join('')}
        </div>
      </section>
    </div>`;
}

function renderBattleLobby() {
  const selected = getGrade(state.selectedGrade);
  const room = roomSession;
  return `
    <div class="page page-battle-lobby">
      <section class="page-heading-row battle-heading">
        <div><div class="eyebrow"><span class="eyebrow-mark"></span> ONLINE ARENA <span class="eyebrow-live">REAL-TIME</span></div><h1>対戦アリーナ</h1><p>同じルール、同じ級。読みの速さだけで勝負しよう。</p></div>
        <div class="queue-status"><span class="pulse-ring"></span><div><b>1,284</b><small>プレイヤーがプレイ中</small></div></div>
      </section>
      <section class="battle-setup-grid">
        <div class="panel setup-panel">
          <div class="panel-heading"><div><div class="eyebrow subtle">MATCH SETTINGS</div><h2>対戦をカスタマイズ</h2></div><span class="setting-lock">● 自動保存</span></div>
          <div class="setting-block"><label class="setting-label">対戦モード</label><div class="mode-switcher">
            <button class="mode-card ${state.selectedMode === 'ranked' ? 'is-selected' : ''}" data-action="select-mode" data-mode="ranked"><span class="mode-icon mode-sword">⚔</span><span><b>ランクマッチ</b><small>レートを賭けて戦う</small></span><i>✓</i></button>
            <button class="mode-card ${state.selectedMode === 'quick' ? 'is-selected' : ''}" data-action="select-mode" data-mode="quick"><span class="mode-icon mode-bolt">ϟ</span><span><b>クイックマッチ</b><small>気軽に5問勝負</small></span><i>✓</i></button>
            <button class="mode-card ${state.selectedMode === 'friend' ? 'is-selected' : ''}" data-action="select-mode" data-mode="friend"><span class="mode-icon mode-link">⌁</span><span><b>フレンドルーム</b><small>ルームコードで招待</small></span><i>✓</i></button>
          </div></div>
          <div class="setting-block grade-setting"><div class="setting-label-row"><label class="setting-label">出題する漢検級</label><span class="setting-value">${selected.label} · ${escapeHtml(selected.difficulty)}</span></div><div class="compact-grade-grid">${GRADE_CONFIG.map((grade) => renderGradeTile(grade, true)).join('')}</div></div>
          ${state.selectedMode === 'friend' ? renderRoomSettings(room) : ''}
          <div class="rule-summary"><div><span class="rule-symbol">Aa</span><b>読みだけ</b><small>答えはひらがな・カタカナ</small></div><div><span class="rule-symbol">5</span><b>BEST OF 5</b><small>全5問の合計スコア</small></div><div><span class="rule-symbol">✦</span><b>意味を公開</b><small>正解後、両者に表示</small></div></div>
          <button class="button button-primary button-wide" data-action="${state.selectedMode === 'friend' ? (room ? 'start-room-match' : 'create-room') : 'start-match'}">${state.selectedMode === 'friend' ? (room ? 'このルームで開始' : 'ルームを作成') : '対戦相手を探す'} <span class="button-arrow">→</span></button>
        </div>
        <div class="arena-rules-card">
          <div class="arena-card-grid"></div><div class="arena-card-glow"></div>
          <div class="arena-card-content"><span class="arena-card-kicker">THE ARENA RULES</span><h2>読めたら、<br><em>意味まで見える。</em></h2><p>正解した瞬間、正しい読みと意味があなたと相手の画面に同時公開されます。</p><div class="rule-visual"><div class="rule-orb">読</div><div class="rule-connector"></div><div class="rule-orb small">意</div><span>REVEAL TO BOTH</span></div></div>
          <div class="arena-card-foot"><span><i class="connection-dot"></i> MATCH SERVERS ONLINE</span><b>32ms</b></div>
        </div>
      </section>
      <section class="lobby-info-grid"><div class="info-card"><span class="info-card-icon">⌁</span><div><b>読みの入力は日本語だけ</b><p>漢字やローマ字は答えとして扱いません。送り仮名も含めて、ひらがなで入力。</p></div></div><div class="info-card"><span class="info-card-icon">✦</span><div><b>漢検基準の12段階</b><p>1級から10級まで、実際の検定の目安に合わせた問題プールを用意しています。</p></div></div><div class="info-card"><span class="info-card-icon">◉</span><div><b>ルームコードで合流</b><p>フレンドモードなら6文字のコードを共有して同じ級で対戦できます。</p></div></div></section>
    </div>`;
}

function renderRoomSettings(room) {
  if (room) {
    return `<div class="room-open-card"><div><span class="room-label">ROOM CODE</span><strong>${escapeHtml(room.code)}</strong><small>フレンドにコードを共有してね · ${room.members || 1} / 2 人</small></div><button class="button button-small button-ghost" data-action="copy-room">コードをコピー</button></div>`;
  }
  return `<div class="room-form-row"><button class="button button-secondary" data-action="create-room"><span>＋</span> 新しいルームを作成</button><span class="room-or">OR</span><form class="join-room-form" data-form="join-room"><input name="roomCode" maxlength="7" placeholder="KJ-XXXXXX" aria-label="ルームコード"><button class="button button-ghost button-small" type="submit">参加する</button></form></div>`;
}

function renderMatchmaking() {
  const selected = getGrade(state.selectedGrade);
  const isRoom = match?.mode === 'friend';
  return `<div class="page page-matchmaking"><div class="matchmaking-shell"><div class="matchmaking-orbit orbit-a"></div><div class="matchmaking-orbit orbit-b"></div><div class="search-emblem"><span>漢</span><i></i></div><div class="eyebrow centered"><span class="eyebrow-mark"></span> ${isRoom ? 'FRIEND ROOM' : 'MATCHMAKING'} <span class="eyebrow-live">ONLINE</span></div><h1>${isRoom ? '対戦準備中…' : '対戦相手を探しています…'}</h1><p>${isRoom ? `ルーム ${escapeHtml(match.roomCode)} · ${selected.label}` : `${selected.label} · ${escapeHtml(selected.difficulty)} · 5問勝負`}</p><div class="search-progress"><span></span></div><div class="search-meta"><span><i class="connection-dot"></i> サーバー接続中</span><b>${isRoom ? '相手が参加するまで待機' : '推定待ち時間 3秒'}</b></div><button class="button button-ghost" data-action="cancel-match">キャンセルして設定に戻る</button><div class="matchmaking-tip"><span>TIP</span> 読みはひらがな・カタカナどちらでも送信できます。</div></div></div>`;
}

function renderCountdown() {
  const current = match.countdownNumber || 3;
  return `<div class="countdown-overlay"><div class="countdown-lines"></div><span class="countdown-label">GET READY · ${escapeHtml(getGrade(match.grade).label)}</span><strong data-countdown-number>${current}</strong><span class="countdown-sub">読みの一撃を準備</span></div>`;
}

function renderPromptHtml(question) {
  const prompt = escapeHtml(question.prompt).replaceAll('\n', '<br>');
  const word = escapeHtml(question.word);
  return prompt.replace(word, `<mark class="prompt-word">${word}</mark>`);
}

function renderAnswerState() {
  if (!match.answered) return '';
  const correct = match.userCorrect;
  return `<div class="answer-reveal ${correct ? 'is-correct' : 'is-wrong'}"><div class="answer-reveal-top"><span class="answer-result-icon">${correct ? '✓' : '×'}</span><div><strong>${correct ? '正解！' : match.userTimedOut ? '時間切れ' : '不正解'}</strong><small>あなたの回答：${match.userAnswer ? escapeHtml(match.userAnswer) : '未入力'}</small></div><span class="reveal-tag"><i></i> 両者に公開</span></div><div class="meaning-reveal"><div class="meaning-reading"><span>正しい読み</span><b>${escapeHtml(match.question.reading)}</b></div><div class="meaning-divider"></div><div class="meaning-copy"><span>意味</span><p>${escapeHtml(match.question.meaning)}</p></div></div></div>`;
}

function renderOpponentStatus() {
  if (!match.opponentAnswered) {
    return `<div class="opponent-answering"><span class="thinking-dots"><i></i><i></i><i></i></span><span>相手が回答中…</span></div>`;
  }
  return `<div class="opponent-answer-result ${match.opponentCorrect ? 'is-correct' : 'is-wrong'}"><span>${match.opponentCorrect ? '✓' : '×'}</span><b>${match.opponentCorrect ? '正解' : '不正解'}</b>${match.opponentCorrect ? '' : `<small>${escapeHtml(match.question.reading)}</small>`}</div>`;
}

function renderBattleFeed() {
  const feed = match.feed || [];
  return `<div class="battle-feed"><div class="feed-label">LIVE FEED</div>${feed.slice(-4).reverse().map((item) => `<div class="feed-item"><span class="feed-dot ${item.type || ''}"></span><span>${escapeHtml(item.text)}</span><time>${escapeHtml(item.time)}</time></div>`).join('')}</div>`;
}

function renderActiveBattle() {
  const question = match.question;
  const grade = getGrade(match.grade);
  const userName = state.profile.name;
  const opponent = match.opponentName || 'KAI';
  const progress = (match.currentIndex / match.questions.length) * 100;
  const answerPanel = match.answered ? '' : `<form class="answer-form" data-form="battle-answer" autocomplete="off"><label for="battle-answer">読みを入力 <span>ひらがな / カタカナ</span></label><div class="answer-input-wrap"><input id="battle-answer" name="answer" inputmode="kana" autocapitalize="none" autocomplete="off" spellcheck="false" placeholder="ひらがなで入力…" maxlength="40" ${match.status !== 'active' ? 'disabled' : ''} autofocus><button type="submit" ${match.status !== 'active' ? 'disabled' : ''}>送信 <span>↵</span></button></div><div class="answer-hint"><span>ENTER</span> で送信 · 漢字入力は無効です</div></form>`;
  return `<div class="page page-battle-active">
    <div class="battle-topline"><div class="battle-mode-label"><span class="live-dot"></span>${match.mode === 'ranked' ? 'RANKED MATCH' : match.mode === 'friend' ? 'FRIEND ROOM' : 'QUICK MATCH'} <span>·</span> ${grade.label}</div><div class="battle-room-chip">${match.mode === 'friend' ? `ROOM ${escapeHtml(match.roomCode)}` : 'LIVE MATCH'} <span class="connection-dot"></span></div><button class="icon-button battle-close" data-action="leave-match" aria-label="退出">×</button></div>
    <div class="battle-scoreboard"><div class="combatant combatant-you"><div class="combatant-name"><span>YOU</span><strong>${escapeHtml(userName)}</strong></div><div class="combatant-score">${match.userScore}<small>PTS</small></div><div class="health-track"><span style="width:${Math.max(0, Math.min(100, (match.userScore / match.questions.length) * 100 + (match.questions.length - match.currentIndex - 1) * 8))}%"></span></div><small class="streak-label">${match.userScore > 1 ? `✦ ${match.userScore} READ STREAK` : 'READY TO READ'}</small></div><div class="round-center"><span>ROUND</span><strong>${String(match.currentIndex + 1).padStart(2, '0')}<i> / ${String(match.questions.length).padStart(2, '0')}</i></strong><div class="round-progress"><span style="width:${progress}%"></span></div></div><div class="combatant combatant-opponent"><div class="combatant-name"><span>OPPONENT</span><strong>${escapeHtml(opponent)}</strong></div><div class="combatant-score">${match.opponentScore}<small>PTS</small></div><div class="health-track opponent-health"><span style="width:${Math.max(0, Math.min(100, (match.opponentScore / match.questions.length) * 100 + (match.questions.length - match.currentIndex - 1) * 8))}%"></span></div><small class="streak-label">${match.opponentScore > 1 ? `✦ ${match.opponentScore} READ STREAK` : 'READING…'}</small></div></div>
    <div class="battle-arena-layout"><aside class="battle-player-card left-card"><div class="player-card-glow"></div><div class="player-card-top"><span class="player-role">YOUR LOADOUT</span><span class="player-level">LV ${state.profile.level}</span></div><div class="battle-avatar-large">${renderAvatar(userName, 'cyan', 'xl')}<span class="avatar-ring ring-cyan"></span></div><strong>${escapeHtml(userName)}</strong><span class="player-rank">RISING READER</span><div class="player-stat-row"><span>RATING <b>${formatRating(state.profile.rating)}</b></span><span>WIN RATE <b>${Math.round((state.profile.wins / Math.max(1, state.profile.wins + state.profile.losses)) * 100)}%</b></span></div><div class="ready-chip"><i></i> ONLINE</div></aside>
      <section class="question-zone"><div class="question-zone-top"><span class="question-badge">${grade.label} · ${escapeHtml(grade.difficulty)}</span><span class="timer ${match.timeLeft <= 5 ? 'is-danger' : ''}"><i class="timer-icon">◷</i><b data-timer>${String(match.timeLeft).padStart(2, '0')}</b><small>SEC</small></span></div><div class="question-card"><div class="question-card-lines"></div><span class="question-card-label">READING CHALLENGE <i></i></span><h2>${renderPromptHtml(question)}</h2><div class="question-context"><span class="context-mark">文</span><span>${escapeHtml(question.sentence)}</span></div>${answerPanel}<div class="reveal-separator"><span>ANSWER REVEAL</span><i></i><small>意味は正解後に両者へ公開</small></div>${renderAnswerState()}${match.answered ? `<button class="button button-primary next-question-button" data-action="next-round">${match.currentIndex === match.questions.length - 1 ? '結果を見る' : '次の問題へ'} <span>→</span></button>` : ''}</div><div class="question-footnote"><span><i class="lock-icon">⌁</i> 読みだけで回答</span><span>Question ID: ${escapeHtml(question.id)}</span></div></section>
      <aside class="battle-player-card right-card"><div class="player-card-top"><span class="player-role">OPPONENT</span><span class="player-level">LV 11</span></div><div class="battle-avatar-large">${renderAvatar(opponent, 'orange', 'xl')}<span class="avatar-ring ring-orange"></span></div><strong>${escapeHtml(opponent)}</strong><span class="player-rank">KANJI RUNNER</span><div class="opponent-answer-box">${renderOpponentStatus()}</div><div class="player-stat-row"><span>RATING <b>1,231</b></span><span>STREAK <b>${Math.max(0, match.opponentScore)}</b></span></div><div class="ready-chip opponent-ready"><i></i> MATCHED</div></aside>
    </div>
    <div class="battle-bottom"><div class="battle-tip"><span>TIP</span> ${match.answered ? '正しい読みと意味は、あなたと相手の両方に公開されています。' : '送り仮名も含めて入力。カタカナでの回答も自動変換されます。'}</div>${renderBattleFeed()}</div>
    ${match.status === 'countdown' ? renderCountdown() : ''}
  </div>`;
}

function renderResult() {
  const won = match.outcome === 'win';
  const draw = match.outcome === 'draw';
  const grade = getGrade(match.grade);
  return `<div class="page page-result"><div class="result-shell ${won ? 'result-win' : draw ? 'result-draw' : 'result-loss'}"><div class="result-confetti"></div><div class="result-kicker">MATCH COMPLETE · ${escapeHtml(grade.label)}</div><div class="result-medal">${won ? '勝' : draw ? '互' : '再'}</div><h1>${won ? '読み勝ち！' : draw ? 'いい勝負！' : '次は取れる。'}</h1><p>${won ? 'あなたの読みが、アリーナを制した。' : draw ? '最後まで互角の読み合いでした。' : '答えを見直して、もう一度挑もう。'}</p><div class="result-score"><div><span>${escapeHtml(state.profile.name)}</span><strong>${match.userScore}</strong><small>正解 ${match.userScore} / ${match.questions.length}</small></div><b>—</b><div><span>${escapeHtml(match.opponentName)}</span><strong>${match.opponentScore}</strong><small>正解 ${match.opponentScore} / ${match.questions.length}</small></div></div><div class="result-rewards"><div><span class="reward-icon">✦</span><b>+${won ? 80 : draw ? 35 : 20} XP</b><small>SEASON XP</small></div><div><span class="reward-icon">◈</span><b>${won ? '+18' : draw ? '+2' : '-8'} Rating</b><small>RATING CHANGE</small></div><div><span class="reward-icon">◎</span><b>${Math.round((match.userScore / match.questions.length) * 100)}%</b><small>ACCURACY</small></div></div><div class="result-actions"><button class="button button-primary" data-action="rematch">もう一度対戦 <span>→</span></button><button class="button button-ghost" data-action="return-dashboard">ダッシュボードへ</button></div><button class="result-link" data-action="review-match">今回の出題と意味を復習する <span>→</span></button></div></div>`;
}

function renderBattle() {
  if (!match) return renderBattleLobby();
  if (match.status === 'searching') return renderMatchmaking();
  if (match.status === 'finished') return renderResult();
  return renderActiveBattle();
}

function renderPractice() {
  const grade = getGrade(state.selectedGrade);
  if (practiceSession) return renderPracticeSession();
  return `<div class="page page-practice"><section class="practice-hero"><div><div class="eyebrow"><span class="eyebrow-mark"></span> SOLO TRAINING</div><h1>一人で磨く、<br><em>読みの反射神経。</em></h1><p>対戦の前に、級別の読みカードでウォームアップ。<br>正解したらすぐに意味を確認できます。</p><button class="button button-primary" data-action="start-practice">${grade.label}で練習を始める <span>→</span></button></div><div class="practice-visual"><div class="practice-card-back">意</div><div class="practice-card-front"><span>READING CARD</span><b>漢</b><small>意味まで覚える</small></div><div class="practice-plus">＋</div></div></section><section class="practice-options"><div class="section-heading"><div><div class="eyebrow subtle">SELECT DECK</div><h2>練習する漢検級</h2></div><span class="deck-total">各級 ${TOTAL_QUESTIONS_PER_GRADE}問</span></div><div class="grade-grid practice-grade-grid">${GRADE_CONFIG.map((item) => renderGradeTile(item)).join('')}</div></section><section class="practice-benefit-grid"><div><span>01</span><b>読みだけに集中</b><p>入力欄は読み専用。漢字の形ではなく、音と意味のつながりを鍛えます。</p></div><div><span>02</span><b>意味を同時に記憶</b><p>回答後は正しい読みと意味をカードで公開。復習がその場で完了。</p></div><div><span>03</span><b>対戦へつながる</b><p>練習の回答数と正解率はあなたのプロフィールに保存されます。</p></div></section></div>`;
}

function renderPracticeSession() {
  const q = practiceSession.question;
  const grade = getGrade(practiceSession.grade);
  const answered = practiceSession.answered;
  return `<div class="page page-practice-session"><div class="practice-session-head"><div><button class="back-button" data-action="finish-practice">← トレーニング選択へ</button><div class="eyebrow subtle">SOLO TRAINING · ${grade.label}</div><h1>読みカード <span>${practiceSession.index + 1} / ${practiceSession.total}</span></h1></div><div class="practice-score-chip"><span>SESSION SCORE</span><b>${practiceSession.score}</b><small>正解</small></div></div><div class="practice-session-grid"><aside class="practice-side-card"><span class="practice-side-label">CURRENT DECK</span><strong>${grade.label}</strong><span>${escapeHtml(grade.difficulty)}</span><div class="practice-progress"><span style="width:${((practiceSession.index + (answered ? 1 : 0)) / practiceSession.total) * 100}%"></span></div><small>${practiceSession.index + (answered ? 1 : 0)} / ${practiceSession.total} cards</small><div class="practice-side-rule"><b>読み only</b><span>答えた後に意味を公開</span></div></aside><section class="practice-card-zone"><div class="practice-question-card ${answered ? (practiceSession.correct ? 'is-correct' : 'is-wrong') : ''}"><div class="question-card-label">READING WARM-UP <i></i></div><span class="practice-question-count">CARD ${String(practiceSession.index + 1).padStart(2, '0')}</span><h2>${renderPromptHtml(q)}</h2><p class="practice-context">${escapeHtml(q.sentence)}</p>${answered ? `<div class="practice-answer-result"><span class="answer-result-icon">${practiceSession.correct ? '✓' : '×'}</span><div><b>${practiceSession.correct ? '正解！' : 'もう一度覚えよう'}</b><small>あなたの回答：${escapeHtml(practiceSession.answer || '未入力')}</small></div></div><div class="practice-meaning"><div><span>正しい読み</span><b>${escapeHtml(q.reading)}</b></div><div><span>意味</span><p>${escapeHtml(q.meaning)}</p></div></div><button class="button button-primary button-wide" data-action="practice-next">次のカードへ <span>→</span></button>` : `<form class="answer-form practice-answer-form" data-form="practice-answer"><label for="practice-answer">読みを入力</label><div class="answer-input-wrap"><input id="practice-answer" name="answer" inputmode="kana" autocomplete="off" spellcheck="false" placeholder="ひらがなで入力…" maxlength="40" autofocus><button type="submit">答える <span>↵</span></button></div><div class="answer-hint"><span>ENTER</span> で送信</div></form>`}</div><div class="practice-footnote"><span>このカードも対戦と同じ漢検基準</span><span>500問のプールから出題</span></div></section></div></div>`;
}

const LEADERBOARD = [
  { rank: 1, name: 'KOTORA', rating: 1832, wins: 94, accent: 'yellow', tag: 'READ MASTER' },
  { rank: 2, name: 'SORA', rating: 1765, wins: 86, accent: 'pink', tag: 'WORD HUNTER' },
  { rank: 3, name: 'YUZU', rating: 1698, wins: 78, accent: 'violet', tag: 'KANJI RUNNER' },
  { rank: 4, name: 'AO', rating: 1612, wins: 73, accent: 'orange', tag: 'FAST READER' },
  { rank: 5, name: 'MIZUKI', rating: 1554, wins: 68, accent: 'cyan', tag: 'RISING READER' },
  { rank: 6, name: 'REN', rating: 1508, wins: 63, accent: 'blue', tag: 'RISING READER' },
];

function renderRankings() {
  const playerRank = 18;
  return `<div class="page page-rankings"><section class="rankings-hero"><div><div class="eyebrow"><span class="eyebrow-mark"></span> SEASON 03 · WEEK 6</div><h1>読む速さを、<br><em>ランキングで証明。</em></h1><p>今シーズンは読みの正確さとスピードで競い合おう。<br>あなたの現在地は全プレイヤーの上位18%。</p></div><div class="rank-emblem"><span>03</span><small>SEASON</small><b>RANKED</b></div></section><div class="ranking-tabs"><button class="is-active">グローバル</button><button>フレンド</button><button>級別ランキング</button><span class="ranking-updated">最終更新：たった今</span></div><section class="ranking-table"><div class="ranking-table-head"><span>RANK</span><span>PLAYER</span><span>BADGE</span><span>WINS</span><span>RATING</span><span></span></div>${LEADERBOARD.map((person) => `<div class="ranking-row ${person.name === state.profile.name ? 'is-you' : ''}"><div class="rank-number rank-${person.rank}">${person.rank <= 3 ? ['♛', '◆', '◆'][person.rank - 1] : person.rank}</div><div class="ranking-player">${renderAvatar(person.name, person.accent, 'sm')}<div><b>${person.name}</b><small>${person.name === state.profile.name ? 'YOU' : `レベル ${Math.max(9, 20 - person.rank)}`}</small></div></div><span class="leader-badge badge-${person.accent}">${person.tag}</span><strong>${person.wins}</strong><strong class="rating-value">${formatRating(person.rating)}</strong><button class="row-more" aria-label="プレイヤー詳細">•••</button></div>`).join('')}<div class="ranking-row is-you"><div class="rank-number">${playerRank}</div><div class="ranking-player">${renderAvatar(state.profile.name, 'cyan', 'sm')}<div><b>${escapeHtml(state.profile.name)}</b><small>YOU · LEVEL ${state.profile.level}</small></div></div><span class="leader-badge badge-cyan">RISING READER</span><strong>${state.profile.wins}</strong><strong class="rating-value">${formatRating(state.profile.rating)}</strong><button class="row-more" aria-label="プレイヤー詳細">•••</button></div></section><section class="rankings-footer-grid"><div class="panel rank-reward"><div><span class="eyebrow subtle">SEASON REWARD</span><h3>あと${playerRank - 10}ランクで<br>限定バッジを獲得</h3><p>シーズン終了まであと18日。毎日一戦で順位を伸ばそう。</p></div><div class="reward-badge">✦<small>TOP<br>10</small></div></div><div class="panel rank-rules"><span class="eyebrow subtle">HOW TO CLIMB</span><h3>レートの仕組み</h3><div><span>WIN</span><b>+18</b><span>DRAW</span><b>+2</b><span>LOSS</span><b>-8</b></div><small>相手とのレート差によって変動します。</small></div></section></div>`;
}

function render() {
  if (!app) return;
  if (state.view === 'dashboard') app.innerHTML = renderDashboard();
  else if (state.view === 'battle') app.innerHTML = renderBattle();
  else if (state.view === 'practice') app.innerHTML = renderPractice();
  else if (state.view === 'rankings') app.innerHTML = renderRankings();
  else app.innerHTML = renderDashboard();
  updateChrome();
  if (state.view === 'battle' && match?.status === 'active' && !match.answered) focusAnswerInput('battle-answer');
  if (state.view === 'practice' && practiceSession && !practiceSession.answered) focusAnswerInput('practice-answer');
}

function focusAnswerInput(id) {
  requestAnimationFrame(() => {
    const input = document.getElementById(id);
    if (input && !input.disabled) input.focus();
  });
}

function clearMatchTimers() {
  Object.keys(matchTimers).forEach((key) => {
    if (matchTimers[key]) clearTimeout(matchTimers[key]);
    if (key === 'clock' && matchTimers[key]) clearInterval(matchTimers[key]);
    matchTimers[key] = null;
  });
}

function pushFeed(text, type = '') {
  if (!match) return;
  if (!match.feed) match.feed = [];
  const now = new Date();
  match.feed.push({ text, type, time: `${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}` });
}

function startMatch(options = {}) {
  clearMatchTimers();
  const mode = options.mode || state.selectedMode;
  const grade = options.grade || state.selectedGrade;
  const roomCode = options.roomCode || roomSession?.code || null;
  match = {
    status: 'searching',
    mode,
    grade: String(grade),
    roomCode,
    opponentName: randomItem(['KAI', 'MIZUKI', 'REN', 'AOI', 'SORA']),
    questions: getRandomQuestions(grade, 5),
    currentIndex: 0,
    question: null,
    userScore: 0,
    opponentScore: 0,
    timeLeft: 15,
    feed: [],
    countdownNumber: 3,
    answered: false,
    opponentAnswered: false,
  };
  state.view = 'battle';
  saveState();
  render();
  matchTimers.search = setTimeout(() => matchFound(), mode === 'friend' ? 1200 : 1750);
}

function matchFound() {
  if (!match || match.status !== 'searching') return;
  match.status = 'countdown';
  match.countdownNumber = 3;
  match.question = match.questions[0];
  pushFeed(`${match.opponentName} がマッチに参加しました`, 'system');
  render();
  let number = 3;
  matchTimers.countdown = setInterval(() => {
    number -= 1;
    if (!match || match.status !== 'countdown') return;
    match.countdownNumber = number;
    const counter = document.querySelector('[data-countdown-number]');
    if (counter) counter.textContent = String(number);
    if (number <= 0) {
      clearInterval(matchTimers.countdown);
      matchTimers.countdown = null;
      beginRound();
    }
  }, 800);
}

function beginRound() {
  if (!match) return;
  clearMatchTimers();
  if (match.currentIndex >= match.questions.length) {
    finishMatch();
    return;
  }
  match.status = 'active';
  match.question = match.questions[match.currentIndex];
  match.timeLeft = 15;
  match.answered = false;
  match.userCorrect = false;
  match.userAnswer = '';
  match.userTimedOut = false;
  match.opponentAnswered = false;
  match.opponentCorrect = false;
  pushFeed(`Round ${match.currentIndex + 1} · ${match.question.id} が出題されました`, 'system');
  render();
  matchTimers.clock = setInterval(() => {
    if (!match || match.status !== 'active') return;
    match.timeLeft -= 1;
    const timer = document.querySelector('[data-timer]');
    if (timer) {
      timer.textContent = String(Math.max(0, match.timeLeft)).padStart(2, '0');
      timer.parentElement?.classList.toggle('is-danger', match.timeLeft <= 5);
    }
    if (match.timeLeft <= 0) submitBattleAnswer('', true);
  }, 1000);
  matchTimers.opponent = setTimeout(() => opponentAnswers(), 3400 + Math.floor(Math.random() * 3800));
}

function opponentAnswers(force = false) {
  if (!match || match.opponentAnswered || match.status === 'finished') return;
  match.opponentAnswered = true;
  match.opponentCorrect = force ? Math.random() > 0.35 : Math.random() > 0.3;
  if (match.opponentCorrect) {
    match.opponentScore += 1;
    pushFeed(`${match.opponentName} が正解しました`, 'opponent');
  } else {
    pushFeed(`${match.opponentName} は読みを外しました`, 'wrong');
  }
  if (match.status !== 'active' || match.answered) render();
}

function submitBattleAnswer(rawAnswer, timedOut = false) {
  if (!match || match.status !== 'active' || match.answered) return;
  clearInterval(matchTimers.clock);
  matchTimers.clock = null;
  const answer = String(rawAnswer || '').trim();
  match.userAnswer = answer;
  match.userTimedOut = timedOut;
  match.userCorrect = !timedOut && normalizeReading(answer) === normalizeReading(match.question.reading);
  match.answered = true;
  match.status = 'reveal';
  if (match.userCorrect) {
    match.userScore += 1;
    pushFeed(`${state.profile.name} が正解 · 意味を公開`, 'correct');
  } else {
    pushFeed(`${state.profile.name} の回答は不正解 · 答えを公開`, 'wrong');
  }
  render();
}

function nextRound() {
  if (!match || !match.answered) return;
  if (!match.opponentAnswered) opponentAnswers(true);
  if (match.currentIndex >= match.questions.length - 1) {
    finishMatch();
    return;
  }
  match.currentIndex += 1;
  beginRound();
}

function finishMatch() {
  if (!match) return;
  clearMatchTimers();
  match.status = 'finished';
  match.outcome = match.userScore > match.opponentScore ? 'win' : match.userScore === match.opponentScore ? 'draw' : 'loss';
  if (!match.recorded) {
    match.recorded = true;
    const win = match.outcome === 'win';
    const draw = match.outcome === 'draw';
    state.stats.matches += 1;
    state.stats.answered += match.questions.length;
    state.stats.correct += match.userScore;
    if (match.userScore === match.questions.length) state.stats.bestStreak = Math.max(state.stats.bestStreak, match.userScore);
    if (win) {
      state.profile.wins += 1;
      state.profile.rating += 18;
      state.profile.streak += 1;
    } else if (draw) {
      state.profile.rating += 2;
      state.profile.streak = 0;
    } else {
      state.profile.losses += 1;
      state.profile.rating = Math.max(0, state.profile.rating - 8);
      state.profile.streak = 0;
    }
    state.profile.xp += win ? 80 : draw ? 35 : 20;
    state.recentMatches.unshift({ opponent: match.opponentName, grade: match.grade, score: `${match.userScore} - ${match.opponentScore}`, result: win ? 'WIN' : draw ? 'DRAW' : 'LOSS', time: 'たった今', accent: win ? 'orange' : 'violet' });
    state.recentMatches = state.recentMatches.slice(0, 4);
    saveState();
  }
  render();
}

function cancelMatch() {
  clearMatchTimers();
  match = null;
  setView('battle');
}

function leaveMatch() {
  if (!match || match.status === 'finished') {
    match = null;
    setView('battle');
    return;
  }
  showConfirmModal('対戦を退出しますか？', 'この対戦のスコアは保存されません。', () => {
    clearMatchTimers();
    match = null;
    render();
  });
}

function createRoom() {
  roomSession = { code: createRoomCode(), members: 1, createdAt: Date.now() };
  saveRoomSession();
  state.selectedMode = 'friend';
  state.view = 'battle';
  saveState();
  render();
  showToast(`ルーム ${roomSession.code} を作成しました`, 'success');
}

function joinRoom(code) {
  const cleaned = String(code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (cleaned.length !== 6) {
    showToast('6文字のルームコードを入力してください', 'error');
    return;
  }
  roomSession = { code: `${cleaned.slice(0, 3)}-${cleaned.slice(3)}`, members: 2, joined: true, createdAt: Date.now() };
  saveRoomSession();
  state.selectedMode = 'friend';
  saveState();
  showToast(`ルーム ${roomSession.code} に参加しました`, 'success');
  setTimeout(() => startMatch({ mode: 'friend', roomCode: roomSession.code }), 500);
}

function startRoomMatch() {
  if (!roomSession) {
    createRoom();
    return;
  }
  startMatch({ mode: 'friend', roomCode: roomSession.code });
}

function startPractice() {
  const grade = state.selectedGrade;
  practiceSession = { grade, question: getRandomQuestions(grade, 1)[0], index: 0, total: 10, score: 0, answered: false, correct: false, answer: '' };
  state.view = 'practice';
  saveState();
  render();
}

function submitPracticeAnswer(rawAnswer) {
  if (!practiceSession || practiceSession.answered) return;
  const answer = String(rawAnswer || '').trim();
  practiceSession.answer = answer;
  practiceSession.correct = normalizeReading(answer) === normalizeReading(practiceSession.question.reading);
  practiceSession.answered = true;
  if (practiceSession.correct) practiceSession.score += 1;
  state.stats.practiceAnswers += 1;
  state.stats.answered += 1;
  if (practiceSession.correct) state.stats.correct += 1;
  state.profile.xp += practiceSession.correct ? 8 : 2;
  saveState();
  render();
}

function nextPracticeCard() {
  if (!practiceSession) return;
  if (practiceSession.index >= practiceSession.total - 1) {
    const score = practiceSession.score;
    practiceSession = null;
    saveState();
    showToast(`トレーニング完了！ ${score} / 10 正解`, score >= 7 ? 'success' : 'default');
    render();
    return;
  }
  practiceSession.index += 1;
  practiceSession.question = getRandomQuestions(practiceSession.grade, 1)[0];
  practiceSession.answered = false;
  practiceSession.correct = false;
  practiceSession.answer = '';
  render();
}

function showModal(content, modalClass = '') {
  modalRoot.innerHTML = `<div class="modal-backdrop" data-action="close-modal"><div class="modal-card ${modalClass}" role="dialog" aria-modal="true" aria-label="Kanji Kombat dialog" data-modal-card>${content}</div></div>`;
  requestAnimationFrame(() => modalRoot.querySelector('.modal-backdrop')?.classList.add('is-visible'));
}

function closeModal() {
  modalRoot.querySelector('.modal-backdrop')?.classList.remove('is-visible');
  setTimeout(() => { modalRoot.innerHTML = ''; }, 180);
}

function showConfirmModal(title, description, onConfirm) {
  showModal(`<button class="modal-close" data-action="close-modal">×</button><div class="modal-symbol warning">!</div><div class="eyebrow subtle">LEAVE MATCH</div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(description)}</p><div class="modal-actions"><button class="button button-ghost" data-action="close-modal">キャンセル</button><button class="button button-danger" data-action="confirm-leave">退出する</button></div>`);
  modalRoot.querySelector('[data-action="confirm-leave"]').onclick = () => { closeModal(); onConfirm(); };
}

function showHelpModal() {
  showModal(`<button class="modal-close" data-action="close-modal">×</button><div class="modal-symbol">漢</div><div class="eyebrow subtle">HOW TO PLAY</div><h2>読みの一撃で勝負。</h2><p class="modal-lead">Kanji Kombatは、漢検の級別難易度で「読み」だけを競うリアルタイムバトルです。</p><div class="help-steps"><div><b>01</b><span>級とモードを選んで対戦を探す</span></div><div><b>02</b><span>15秒以内に読みを入力する</span></div><div><b>03</b><span>正解したら、読みと意味が両者に公開</span></div></div><div class="modal-rule-note"><span>読み only</span> 漢字・ローマ字の入力は正解になりません。ひらがな・カタカナに対応しています。</div><button class="button button-primary button-wide" data-action="close-modal">ルールを理解した</button>`);
}

function showNotificationsModal() {
  state.notifications = 0;
  saveState();
  updateChrome();
  showModal(`<button class="modal-close" data-action="close-modal">×</button><div class="modal-header-row"><div><div class="eyebrow subtle">INBOX</div><h2>通知</h2></div><span class="notification-clear">すべて既読</span></div><div class="notification-list"><div class="notification-row is-new"><span class="notification-icon pink">✦</span><div><b>新しいシーズンが始まりました</b><p>Season 03「読む速さで、証明。」開催中。</p><time>12分前</time></div></div><div class="notification-row is-new"><span class="notification-icon cyan">⚔</span><div><b>デイリーミッション更新</b><p>今日のチャレンジを3つ達成してXPを獲得しよう。</p><time>1時間前</time></div></div><div class="notification-row"><span class="notification-icon gold">◎</span><div><b>ランキングが更新されました</b><p>あなたは現在、全体の18位です。</p><time>昨日</time></div></div></div>`);
}

function showProfileModal() {
  const winRate = Math.round((state.profile.wins / Math.max(1, state.profile.wins + state.profile.losses)) * 100);
  showModal(`<button class="modal-close" data-action="close-modal">×</button><div class="profile-modal-head">${renderAvatar(state.profile.name, 'cyan', 'lg')}<div><div class="eyebrow subtle">PLAYER PROFILE</div><h2>${escapeHtml(state.profile.name)}</h2><span>RISING READER · LEVEL ${state.profile.level}</span></div></div><div class="profile-modal-stats"><div><b>${formatRating(state.profile.rating)}</b><small>RATING</small></div><div><b>${winRate}%</b><small>WIN RATE</small></div><div><b>${state.profile.streak}</b><small>STREAK</small></div></div><div class="profile-xp"><div><span>SEASON XP</span><b>${formatNumber(state.profile.xp)} / ${formatNumber(Math.ceil(state.profile.xp / 1000) * 1000)}</b></div><div class="progress-track"><span style="width:${(state.profile.xp % 1000) / 10}%"></span></div></div><button class="button button-ghost button-wide" data-action="close-modal">閉じる</button>`);
}

function reviewMatch() {
  if (!match) return;
  const rows = match.questions.map((question, index) => `<div class="review-row"><span>${String(index + 1).padStart(2, '0')}</span><b>${escapeHtml(question.word)}</b><strong>${escapeHtml(question.reading)}</strong><p>${escapeHtml(question.meaning)}</p></div>`).join('');
  showModal(`<button class="modal-close" data-action="close-modal">×</button><div class="eyebrow subtle">MATCH REVIEW · ${escapeHtml(getGrade(match.grade).label)}</div><h2>今回の出題カード</h2><p>読みと意味をもう一度チェック。</p><div class="review-list">${rows}</div><button class="button button-primary button-wide" data-action="close-modal">閉じる</button>`, 'review-modal');
}

function copyRoomCode() {
  if (!roomSession) return;
  const code = roomSession.code;
  if (navigator.clipboard?.writeText) navigator.clipboard.writeText(code).catch(() => {});
  showToast(`ルームコード ${code} をコピーしました`, 'success');
}

document.addEventListener('click', (event) => {
  const viewButton = event.target.closest('[data-view]');
  if (viewButton && !viewButton.dataset.action) {
    setView(viewButton.dataset.view);
    return;
  }
  const actionElement = event.target.closest('[data-action]');
  if (!actionElement) return;
  const action = actionElement.dataset.action;
  if (action === 'close-modal' && actionElement.classList.contains('modal-backdrop') && event.target !== actionElement) return;
  if (action === 'select-grade') { setGrade(actionElement.dataset.grade); return; }
  if (action === 'select-mode') { setMode(actionElement.dataset.mode); return; }
  if (action === 'start-match') { startMatch(); return; }
  if (action === 'open-practice') { setView('practice'); return; }
  if (action === 'start-practice') { startPractice(); return; }
  if (action === 'practice-next') { nextPracticeCard(); return; }
  if (action === 'finish-practice') { practiceSession = null; setView('practice'); return; }
  if (action === 'next-round') { nextRound(); return; }
  if (action === 'cancel-match') { cancelMatch(); return; }
  if (action === 'leave-match') { leaveMatch(); return; }
  if (action === 'create-room') { createRoom(); return; }
  if (action === 'start-room-match') { startRoomMatch(); return; }
  if (action === 'copy-room') { copyRoomCode(); return; }
  if (action === 'rematch') { startMatch({ mode: match.mode, grade: match.grade, roomCode: match.roomCode }); return; }
  if (action === 'return-dashboard') { match = null; setView('dashboard'); return; }
  if (action === 'review-match') { reviewMatch(); return; }
  if (action === 'notifications') { showNotificationsModal(); return; }
  if (action === 'show-help') { showHelpModal(); return; }
  if (action === 'profile') { showProfileModal(); return; }
  if (action === 'close-modal') { closeModal(); return; }
  if (action === 'show-history') { showToast('対戦履歴はこの画面に最新4件を表示しています', 'default'); return; }
});

document.addEventListener('submit', (event) => {
  const form = event.target.closest('form');
  if (!form) return;
  event.preventDefault();
  const formData = new FormData(form);
  if (form.dataset.form === 'battle-answer') {
    submitBattleAnswer(formData.get('answer'));
  } else if (form.dataset.form === 'practice-answer') {
    submitPracticeAnswer(formData.get('answer'));
  } else if (form.dataset.form === 'join-room') {
    joinRoom(formData.get('roomCode'));
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && modalRoot.innerHTML) closeModal();
});

window.addEventListener('beforeunload', () => clearMatchTimers());

render();
