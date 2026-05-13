/// HTML/CSS/JS bundle served at `/` when WerewolfServer is hosting.
/// Vanilla JS, no build step. Speaks the same JSON protocol as
/// WerewolfServer.
const String werewolfBrowserHtml = r'''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Werewolf</title>
<style>
  :root {
    color-scheme: dark;
    --bg: #0d1117;
    --card: #161b22;
    --card2: #21262d;
    --line: #30363d;
    --text: #e6edf3;
    --muted: #9da7b3;
    --accent: #5865f2;
    --danger: #f85149;
    --good: #2ea043;
    --warn: #d29922;
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    margin: 0;
    padding: env(safe-area-inset-top) 16px env(safe-area-inset-bottom);
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, system-ui, sans-serif;
    -webkit-tap-highlight-color: transparent;
  }
  .wrap { max-width: 480px; margin: 0 auto; padding: 24px 0; }
  h1 { font-size: 28px; margin: 0 0 16px; letter-spacing: -0.5px; }
  h2 { font-size: 14px; margin: 24px 0 8px; color: var(--muted); text-transform: uppercase; letter-spacing: 1.2px; }
  .card { background: var(--card); border-radius: 16px; padding: 20px; margin-bottom: 16px; }
  .pill { display: inline-block; background: var(--card2); padding: 4px 10px; border-radius: 999px; font-size: 12px; color: var(--muted); }
  .pill.live { background: var(--good); color: #fff; }
  .pill.dead { background: var(--danger); color: #fff; }
  .pill.you { background: var(--accent); color: #fff; }
  button, input[type="text"] {
    width: 100%;
    font-size: 16px;
    padding: 14px 16px;
    border-radius: 12px;
    border: 1px solid var(--line);
    background: var(--card2);
    color: var(--text);
    font-family: inherit;
  }
  button {
    background: var(--accent);
    color: #fff;
    border: none;
    font-weight: 600;
    cursor: pointer;
  }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  button.secondary { background: var(--card2); color: var(--text); border: 1px solid var(--line); }
  button.danger { background: var(--danger); }
  .player-list { display: flex; flex-direction: column; gap: 8px; margin-top: 8px; }
  .player {
    display: flex; align-items: center; justify-content: space-between;
    background: var(--card2); padding: 12px 16px; border-radius: 12px;
  }
  .player .name { font-weight: 500; }
  .target-grid { display: grid; gap: 8px; }
  .target {
    width: 100%;
    background: var(--card2);
    border: 1px solid var(--line);
    color: var(--text);
    padding: 16px;
    border-radius: 12px;
    font-size: 16px;
    text-align: left;
  }
  .target.selected { background: var(--accent); border-color: var(--accent); color: #fff; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 8px; font-size: 11px; font-weight: 600; }
  .b-werewolf { background: #4c1d24; color: #ff8a8a; }
  .b-seer { background: #2a2050; color: #c4cfff; }
  .b-hunter { background: #4d3a14; color: #ffd97a; }
  .b-villager { background: var(--card2); color: var(--muted); }
  .role-card { padding: 28px; text-align: center; border-radius: 20px; }
  .role-card h1 { font-size: 36px; margin: 8px 0; }
  .role-card.werewolf { background: linear-gradient(160deg, #5b1d2c, #2a1116); }
  .role-card.seer { background: linear-gradient(160deg, #2a2050, #110d28); }
  .role-card.hunter { background: linear-gradient(160deg, #4d3a14, #25190a); }
  .role-card.villager { background: linear-gradient(160deg, #1f2a3a, #0f1620); }
  .phase-banner {
    text-align: center; padding: 20px; border-radius: 16px; margin-bottom: 16px;
    font-size: 22px; font-weight: 700;
  }
  .phase-night { background: linear-gradient(160deg, #1f2540, #0f1530); color: #c4cfff; }
  .phase-day_vote { background: linear-gradient(160deg, #4d3a14, #25190a); color: #ffd97a; }
  .phase-day_reveal { background: linear-gradient(160deg, #3a2440, #1a0f1d); color: #e6c4ff; }
  .phase-hunter_shot { background: linear-gradient(160deg, #4d1414, #250a0a); color: #ff8a8a; }
  .phase-game_over { background: linear-gradient(160deg, #1d4a36, #0d2a1f); color: #6ee7a8; }
  .seer-result { padding: 16px; border-radius: 12px; margin-bottom: 12px; text-align: center; font-weight: 600; }
  .seer-result.wolf { background: #4c1d24; color: #ff8a8a; }
  .seer-result.clean { background: #1f3b2c; color: #6ee7a8; }
  .small { color: var(--muted); font-size: 13px; }
  .center { text-align: center; }
  .spinner {
    display: inline-block; width: 18px; height: 18px;
    border: 2px solid var(--line); border-top-color: var(--accent);
    border-radius: 50%; animation: spin 0.8s linear infinite;
    vertical-align: middle; margin-right: 8px;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .error { background: var(--danger); color: #fff; padding: 12px 16px; border-radius: 12px; margin-bottom: 12px; }
</style>
</head>
<body>
<div class="wrap" id="root"></div>

<script>
(() => {
  const root = document.getElementById('root');
  const ws = new WebSocket(`ws://${location.host}/ws`);

  let state = {
    connected: false,
    me: null,                 // {id, name}
    role: null,               // 'werewolf' | 'seer' | 'hunter' | 'villager'
    wolfIds: [],
    phase: 'lobby',
    day: 0,
    alive: [],
    dead: [],
    lobby: [],
    lastNight: null,          // {killedId}
    lastDay: null,            // {eliminatedId, eliminatedRole, tally}
    seerResults: [],          // [{targetId, isWerewolf, day}]
    hunterId: null,           // who currently needs to shoot
    hunterHistory: [],        // [{hunterId, targetId, targetRole}]
    winner: null,
    rolesReveal: null,
    error: null,
    pickedTarget: null,
    submittedPhaseDay: null,
    submittedPhase: null,
  };

  function send(obj) {
    if (ws.readyState === 1) ws.send(JSON.stringify(obj));
  }

  ws.addEventListener('open', () => { state.connected = true; render(); });
  ws.addEventListener('close', () => { state.connected = false; render(); });
  ws.addEventListener('message', (e) => {
    let m;
    try { m = JSON.parse(e.data); } catch { return; }
    handle(m);
    render();
  });

  function handle(m) {
    switch (m.type) {
      case 'welcome':
        state.me = { id: m.yourId, name: m.yourName };
        break;
      case 'lobby':
        state.lobby = m.players;
        break;
      case 'role':
        state.role = m.role;
        state.wolfIds = m.wolfIds || [];
        break;
      case 'phase':
        const phaseChanged = state.phase !== m.phase || state.day !== m.day;
        state.phase = m.phase;
        state.day = m.day;
        state.alive = m.alive || [];
        state.dead = m.dead || [];
        if (m.killedId !== undefined) {
          state.lastNight = { killedId: m.killedId };
        }
        if (phaseChanged) state.pickedTarget = null;
        break;
      case 'vote_update':
        state.dayVotes = m.votes;
        break;
      case 'day_result':
        state.lastDay = m;
        state.alive = m.alive;
        state.dead = m.dead;
        break;
      case 'seer_result':
        state.seerResults.push({ targetId: m.targetId, isWerewolf: m.isWerewolf, day: state.day });
        break;
      case 'hunter_prompt':
        state.phase = 'hunterShot';
        state.hunterId = m.hunterId;
        state.alive = m.alive;
        state.dead = m.dead;
        state.pickedTarget = null;
        break;
      case 'hunter_shot_result':
        state.hunterHistory.push({ hunterId: m.hunterId, targetId: m.targetId, targetRole: m.targetRole });
        state.alive = m.alive;
        state.dead = m.dead;
        break;
      case 'game_over':
        state.phase = 'gameOver';
        state.winner = m.winner;
        state.rolesReveal = m.roles;
        break;
      case 'error':
        state.error = m.message;
        setTimeout(() => { state.error = null; render(); }, 3000);
        break;
    }
  }

  // --- views ---

  function viewConnect() {
    const status = state.connected ? 'Connected' : 'Connecting…';
    return `
      <h1>Werewolf</h1>
      <div class="card">
        <p class="small">${status}</p>
        <h2>Pick a name</h2>
        <input id="name-input" type="text" placeholder="Your name" maxlength="20" autofocus>
        <div style="height:12px"></div>
        <button id="join-btn">Join the village</button>
      </div>
    `;
  }

  function bindConnect() {
    const input = document.getElementById('name-input');
    const btn = document.getElementById('join-btn');
    if (!input || !btn) return;
    const submit = () => {
      const name = input.value.trim();
      if (!name) return;
      send({ type: 'join', name });
    };
    btn.addEventListener('click', submit);
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
  }

  function viewLobby() {
    return `
      <h1>Lobby</h1>
      <div class="card">
        <p class="small">Waiting for the host to start the game.</p>
        <h2>Players (${state.lobby.length})</h2>
        <div class="player-list">
          ${state.lobby.map(p => `
            <div class="player">
              <span class="name">${escapeHtml(p.name)}${p.isHost ? ' <span class="pill">host</span>' : ''}</span>
              ${state.me && p.id === state.me.id ? '<span class="pill you">you</span>' : ''}
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  function viewRoleReveal() {
    if (!state.role) return '';
    const desc = {
      werewolf: 'Hunt the village. You can see your pack.',
      seer: 'Each night, learn whether one player is a werewolf.',
      hunter: 'When you die, you take one player down with you.',
      villager: 'No special ability. Survive and vote wisely.',
    }[state.role];
    const wolfList = state.role === 'werewolf' && state.wolfIds.length > 1
      ? `<p class="small">Your pack: ${state.wolfIds.filter(id => id !== state.me.id).map(id => escapeHtml(playerName(id))).join(', ')}</p>`
      : '';
    return `
      <div class="role-card ${state.role}">
        <p class="badge b-${state.role}">YOUR ROLE</p>
        <h1>${capitalize(state.role)}</h1>
        <p class="small">${desc}</p>
        ${wolfList}
      </div>
    `;
  }

  function viewSeerHistory() {
    if (state.role !== 'seer' || state.seerResults.length === 0) return '';
    return `
      <div class="card">
        <h2>Seer findings</h2>
        ${state.seerResults.map(r => `
          <div class="seer-result ${r.isWerewolf ? 'wolf' : 'clean'}">
            Night ${r.day}: ${escapeHtml(playerName(r.targetId))} ${r.isWerewolf ? 'IS a werewolf' : 'is not a werewolf'}
          </div>
        `).join('')}
      </div>
    `;
  }

  function viewNight() {
    const me = me_();
    if (!me || !me.alive) return viewSpectator();
    const role = state.role;
    if (role === 'werewolf') return viewNightAction('Choose a victim', otherAlive().filter(p => !state.wolfIds.includes(p.id)));
    if (role === 'seer') return viewNightAction('Choose a player to investigate', otherAlive());
    return `
      <div class="phase-banner phase-night">Night ${state.day}</div>
      ${viewRoleReveal()}
      ${viewSeerHistory()}
      <div class="card center">
        <p><span class="spinner"></span> The wolves and the seer are acting…</p>
      </div>
    `;
  }

  function viewNightAction(prompt, targets) {
    const submitted = state.submittedPhase === 'night' && state.submittedPhaseDay === state.day;
    return `
      <div class="phase-banner phase-night">Night ${state.day}</div>
      ${viewRoleReveal()}
      ${viewSeerHistory()}
      <div class="card">
        <h2>${prompt}</h2>
        <div class="target-grid">
          ${targets.map(p => `
            <button class="target ${state.pickedTarget === p.id ? 'selected' : ''}" data-target="${p.id}" ${submitted ? 'disabled' : ''}>
              ${escapeHtml(p.name)}
            </button>
          `).join('')}
        </div>
        <div style="height:12px"></div>
        <button id="confirm" ${submitted || !state.pickedTarget ? 'disabled' : ''}>${submitted ? 'Submitted ✓' : 'Confirm'}</button>
      </div>
    `;
  }

  function bindNightAction() {
    document.querySelectorAll('.target').forEach(btn => {
      btn.addEventListener('click', () => {
        state.pickedTarget = btn.dataset.target;
        render();
      });
    });
    const confirm = document.getElementById('confirm');
    if (confirm) confirm.addEventListener('click', () => {
      send({ type: 'night_action', targetId: state.pickedTarget });
      state.submittedPhase = 'night';
      state.submittedPhaseDay = state.day;
      render();
    });
  }

  function viewDayVote() {
    const me = me_();
    if (!me || !me.alive) return viewSpectator();
    const submitted = state.submittedPhase === 'day' && state.submittedPhaseDay === state.day;
    return `
      <div class="phase-banner phase-day_vote">Day ${state.day} — Vote</div>
      ${viewLastNight()}
      ${viewSeerHistory()}
      <div class="card">
        <h2>Vote to lynch</h2>
        <div class="target-grid">
          ${otherAlive().map(p => `
            <button class="target ${state.pickedTarget === p.id ? 'selected' : ''}" data-target="${p.id}" ${submitted ? 'disabled' : ''}>
              ${escapeHtml(p.name)}
            </button>
          `).join('')}
          <button class="target ${state.pickedTarget === '__skip' ? 'selected' : ''}" data-target="__skip" ${submitted ? 'disabled' : ''}>
            Skip vote
          </button>
        </div>
        <div style="height:12px"></div>
        <button id="confirm" ${submitted || !state.pickedTarget ? 'disabled' : ''}>${submitted ? 'Vote in ✓' : 'Lock in vote'}</button>
      </div>
    `;
  }

  function bindDayVote() {
    document.querySelectorAll('.target').forEach(btn => {
      btn.addEventListener('click', () => {
        state.pickedTarget = btn.dataset.target;
        render();
      });
    });
    const confirm = document.getElementById('confirm');
    if (confirm) confirm.addEventListener('click', () => {
      const target = state.pickedTarget === '__skip' ? null : state.pickedTarget;
      send({ type: 'vote', targetId: target });
      state.submittedPhase = 'day';
      state.submittedPhaseDay = state.day;
      render();
    });
  }

  function viewHunterShot() {
    const isMe = state.me && state.hunterId === state.me.id;
    if (!isMe) {
      return `
        <div class="phase-banner phase-hunter_shot">Hunter's last shot</div>
        <div class="card center">
          <p><span class="spinner"></span> ${escapeHtml(playerName(state.hunterId))} is choosing someone to take down…</p>
        </div>
        ${viewHunterHistory()}
      `;
    }
    return `
      <div class="phase-banner phase-hunter_shot">Your last shot</div>
      <div class="card">
        <h2>You died. Take one with you.</h2>
        <div class="target-grid">
          ${otherAlive().map(p => `
            <button class="target ${state.pickedTarget === p.id ? 'selected' : ''}" data-target="${p.id}">
              ${escapeHtml(p.name)}
            </button>
          `).join('')}
        </div>
        <div style="height:12px"></div>
        <button id="confirm-hunter" ${!state.pickedTarget ? 'disabled' : ''}>Fire</button>
      </div>
      ${viewHunterHistory()}
    `;
  }

  function bindHunterShot() {
    document.querySelectorAll('.target').forEach(btn => {
      btn.addEventListener('click', () => {
        state.pickedTarget = btn.dataset.target;
        render();
      });
    });
    const confirm = document.getElementById('confirm-hunter');
    if (confirm) confirm.addEventListener('click', () => {
      send({ type: 'hunter_shot', targetId: state.pickedTarget });
    });
  }

  function viewHunterHistory() {
    if (state.hunterHistory.length === 0) return '';
    return `
      <div class="card">
        <h2>Hunter shots</h2>
        ${state.hunterHistory.map(h => `
          <div class="player">
            <span class="name">${escapeHtml(playerName(h.hunterId))} → ${escapeHtml(playerName(h.targetId))}</span>
            <span class="badge b-${h.targetRole}">${h.targetRole}</span>
          </div>
        `).join('')}
      </div>
    `;
  }

  function viewLastNight() {
    if (!state.lastNight) return '';
    const n = state.lastNight;
    if (n.killedId) {
      return `<div class="card center"><p>${escapeHtml(playerName(n.killedId))} was killed in the night.</p></div>`;
    }
    return `<div class="card center"><p>A quiet night. No one died.</p></div>`;
  }

  function viewLastDay() {
    if (!state.lastDay) return '';
    const d = state.lastDay;
    if (!d.eliminatedId) {
      return `<div class="card center"><p>The vote tied. No one was lynched.</p></div>`;
    }
    return `<div class="card center"><p>${escapeHtml(playerName(d.eliminatedId))} was lynched — they were a <span class="badge b-${d.eliminatedRole}">${d.eliminatedRole}</span>.</p></div>`;
  }

  function viewSpectator() {
    return `
      <div class="phase-banner phase-day_reveal">You're out</div>
      <div class="card center">
        <p>Watching from the sidelines.</p>
      </div>
    `;
  }

  function viewGameOver() {
    return `
      <div class="phase-banner phase-game_over">${state.winner === 'werewolves' ? 'Werewolves win' : 'Village wins'}</div>
      <div class="card">
        <h2>Roles</h2>
        <div class="player-list">
          ${Object.entries(state.rolesReveal || {}).map(([id, r]) => `
            <div class="player">
              <span class="name">${escapeHtml(playerName(id))}</span>
              <span class="badge b-${r}">${r}</span>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  function viewPlayers() {
    return `
      <h2>Alive (${state.alive.length})</h2>
      <div class="player-list">
        ${state.alive.map(p => `
          <div class="player">
            <span class="name">${escapeHtml(p.name)}${state.me && p.id === state.me.id ? ' <span class="pill you">you</span>' : ''}</span>
            <span class="pill live">alive</span>
          </div>
        `).join('')}
      </div>
      ${state.dead.length > 0 ? `
        <h2>Dead</h2>
        <div class="player-list">
          ${state.dead.map(p => `
            <div class="player">
              <span class="name">${escapeHtml(p.name)}</span>
              <span class="pill dead">dead</span>
            </div>
          `).join('')}
        </div>
      ` : ''}
    `;
  }

  function render() {
    let body = '';
    if (state.error) body += `<div class="error">${escapeHtml(state.error)}</div>`;

    if (!state.me) {
      body += viewConnect();
    } else if (state.phase === 'lobby') {
      body += viewLobby();
    } else if (state.phase === 'gameOver') {
      body += viewGameOver();
    } else if (state.phase === 'night') {
      body += viewNight() + viewPlayers();
    } else if (state.phase === 'dayVote') {
      body += viewDayVote() + viewLastDay() + viewPlayers();
    } else if (state.phase === 'dayReveal') {
      body += `<div class="phase-banner phase-day_reveal">Day ${state.day}</div>`;
      body += viewLastNight() + viewSeerHistory() + viewPlayers();
    } else if (state.phase === 'hunterShot') {
      body += viewHunterShot() + viewPlayers();
    } else {
      body += viewLobby();
    }

    root.innerHTML = body;

    bindConnect();
    if (state.phase === 'night' || state.phase === 'dayVote') {
      bindNightAction();
      bindDayVote();
    }
    if (state.phase === 'hunterShot') {
      bindHunterShot();
    }
  }

  // --- helpers ---
  function me_() {
    if (!state.me) return null;
    return [...state.alive, ...state.dead].find(p => p.id === state.me.id);
  }
  function otherAlive() {
    if (!state.me) return state.alive;
    return state.alive.filter(p => p.id !== state.me.id);
  }
  function playerName(id) {
    const p = [...state.alive, ...state.dead, ...state.lobby].find(p => p.id === id);
    return p ? p.name : id;
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }
  function capitalize(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

  render();
})();
</script>
</body>
</html>
''';
