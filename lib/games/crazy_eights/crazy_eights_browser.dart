/// Browser bundle for Crazy Eights guests. Vanilla HTML/CSS/JS.
const String crazyEightsBrowserHtml = r'''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Crazy Eights</title>
<style>
  :root { color-scheme: dark; --bg:#0a3622; --table:#0d4429; --card:#161b22;
    --line:#30363d; --text:#e6edf3; --muted:#9da7b3; --accent:#2ea043; --warn:#d29922; --danger:#f85149; }
  * { box-sizing:border-box; }
  body { margin:0; padding:env(safe-area-inset-top) 16px env(safe-area-inset-bottom);
    background:var(--bg); color:var(--text); font-family:-apple-system, system-ui, sans-serif; }
  .wrap { max-width:600px; margin:0 auto; padding:16px 0; }
  h1 { font-size:24px; margin:0 0 12px; }
  h2 { font-size:13px; margin:18px 0 8px; color:var(--muted); text-transform:uppercase; letter-spacing:1.2px; }
  .panel { background:var(--card); padding:16px; border-radius:14px; margin-bottom:12px; }
  button, input[type=text] { width:100%; font-size:16px; padding:14px 16px; border-radius:12px;
    border:1px solid var(--line); background:#21262d; color:var(--text); font-family:inherit; }
  button { background:var(--accent); color:#fff; border:none; font-weight:600; cursor:pointer; }
  button:disabled { opacity:.5; cursor:not-allowed; }
  button.warn { background:var(--warn); color:#1c1300; }
  button.gray { background:#30363d; color:var(--text); }

  .table { background:var(--table); border-radius:18px; padding:18px; text-align:center; margin-bottom:12px; box-shadow: inset 0 0 60px rgba(0,0,0,.3); }
  .top { display:flex; justify-content:center; align-items:center; gap:18px; margin-bottom:6px; }
  .pile { width:88px; height:128px; border-radius:12px; display:flex; align-items:center; justify-content:center; font-weight:800; font-size:36px; }
  .pile.draw { background:#0d2a1f; border:2px dashed rgba(255,255,255,.25); color:rgba(255,255,255,.4); cursor:pointer; }
  .pile.draw.disabled { cursor:not-allowed; opacity:.5; }
  .pile.discard { background:#fff; color:#000; }
  .pile.discard.red { color:#c62828; }
  .pile small { display:block; font-size:11px; color:var(--muted); font-weight:500; margin-top:4px; }
  .turn-info { font-size:14px; color:rgba(255,255,255,.85); margin-top:8px; }
  .active-suit { font-size:18px; }

  .hand { display:flex; flex-wrap:wrap; gap:6px; padding:8px; background:rgba(0,0,0,.2); border-radius:14px; }
  .card { width:64px; height:96px; background:#fff; color:#000; border-radius:10px; padding:6px; cursor:pointer; user-select:none;
    display:flex; flex-direction:column; justify-content:space-between; box-shadow:0 2px 4px rgba(0,0,0,.3); transition:transform .12s; }
  .card.red { color:#c62828; }
  .card.unplayable { opacity:.4; cursor:not-allowed; filter:grayscale(.5); }
  .card.selected { transform:translateY(-12px); box-shadow:0 8px 16px rgba(0,0,0,.5); }
  .card .rank { font-size:18px; font-weight:700; line-height:1; }
  .card .suit { font-size:24px; line-height:1; align-self:flex-end; }

  .players { display:flex; gap:8px; overflow-x:auto; padding:8px 0; }
  .pchip { background:#21262d; padding:8px 12px; border-radius:10px; min-width:90px; flex:0 0 auto; }
  .pchip.current { background:var(--accent); color:#fff; }
  .pchip .name { font-size:13px; font-weight:600; }
  .pchip .hc { font-size:11px; opacity:.8; }

  .suit-picker { display:grid; grid-template-columns:repeat(2,1fr); gap:8px; }
  .suit-picker button { font-size:32px; padding:18px; }
  .modal { position:fixed; inset:0; background:rgba(0,0,0,.7); display:flex; align-items:center; justify-content:center; z-index:99; }
  .modal .panel { max-width:360px; width:90%; }
  .vote-row { display:flex; gap:8px; }
  .vote-row button { flex:1; }
  .vote-yes { background:#2ea043; }
  .vote-no { background:#f85149; }
  .vote-yes.selected, .vote-no.selected { outline:3px solid #fff; }
  .tutorial-banner { background:linear-gradient(160deg, #1d4a36, #0d2a1f); color:#6ee7a8; padding:18px; border-radius:14px; margin-bottom:12px; text-align:center; font-weight:600; }
  .tutorial-card { background:linear-gradient(160deg, #1d4a36, #0d2a1f); color:#e6edf3; padding:20px; border-radius:14px; margin-bottom:12px; }
  .tutorial-card h2 { color:#6ee7a8; font-size:18px; margin:0 0 8px; letter-spacing:0; text-transform:none; }
  .tutorial-card h3 { font-size:14px; margin:12px 0 4px; color:#e6edf3; text-transform:none; letter-spacing:0; }
  .tutorial-card p { margin:4px 0; color:#cfd8de; font-size:14px; line-height:1.45; }
  .tutorial-card .t-sec { margin-top:6px; }
  .tutorial-card .menu-label { color:#6ee7a8; font-size:16px; margin:18px 0 6px; font-weight:700; }
  .tutorial-card .wait { color:#9da7b3; font-size:13px; margin-top:14px; }
</style>
</head>
<body>
<div class="wrap" id="root"></div>
<script>
(() => {
  const root = document.getElementById('root');
  const ws = new WebSocket(`ws://${location.host}/ws`);
  const state = { me:null, phase:'lobby', players:[], hand:[], topCard:null, activeSuit:null,
    drawCount:0, currentId:null, winnerId:null, lastEvent:'', justDrew:false, picked:null, pickingSuitFor:null,
    tutorial:{isOpen:false,yesCount:0,noCount:0,eligibleCount:0,result:null,tutorialShown:false}, tutorialContent:null, myTutorialVote:null };

  function send(o){ if (ws.readyState===1) ws.send(JSON.stringify(o)); }

  ws.addEventListener('message', e => {
    let m; try { m=JSON.parse(e.data); } catch { return; }
    switch (m.type) {
      case 'welcome': state.me = { id:m.yourId, name:m.yourName }; break;
      case 'lobby': state.players = m.players; state.phase='lobby'; break;
      case 'state': Object.assign(state, m); state.picked=null; state.pickingSuitFor=null; break;
      case 'hand': state.hand = m.cards; break;
      case 'over': state.phase='gameOver'; state.winnerId=m.winnerId; state.players=m.players; break;
      case 'reset': state.phase='lobby'; state.hand=[]; state.winnerId=null; break;
      case 'tutorial_vote_state': {
        const wasOpen = state.tutorial.isOpen;
        state.tutorial = { isOpen:m.isOpen, yesCount:m.yesCount, noCount:m.noCount, eligibleCount:m.eligibleCount, result:m.result, tutorialShown:m.tutorialShown };
        if (m.title) state.tutorialContent = { title:m.title, sections:m.sections || [], menuSections:m.menuSections || [] };
        if (!wasOpen && m.isOpen) state.myTutorialVote = null;
        break;
      }
    }
    render();
  });

  function render(){
    if (!state.me) {
      root.innerHTML = `<h1>Crazy Eights</h1><div class="panel"><h2>Pick a name</h2><input id="n" type="text" placeholder="Your name" maxlength="20" autofocus><div style="height:12px"></div><button id="b">Join</button></div>`;
      bindJoin(); return;
    }
    if (state.phase==='lobby') return renderLobby();
    if (state.phase==='gameOver') return renderOver();
    return renderTable();
  }

  function bindJoin(){
    const i=document.getElementById('n'), b=document.getElementById('b');
    if (!i||!b) return;
    const submit=()=>{ const n=i.value.trim(); if (n) send({type:'join', name:n}); };
    b.addEventListener('click', submit);
    i.addEventListener('keydown', e => { if (e.key==='Enter') submit(); });
  }

  function renderLobby(){
    root.innerHTML = `<h1>Lobby</h1>${viewTutorialBanner()}${viewTutorialVote()}<div class="panel"><p>Waiting for the host to deal.</p><h2>Players (${state.players.length})</h2>${state.players.map(p=>`<div class="pchip" style="margin-bottom:6px"><div class="name">${esc(p.name)}${p.isHost?' • host':''}${state.me.id===p.id?' • you':''}</div></div>`).join('')}</div>`;
    bindTutorialVote();
  }

  function viewTutorialBanner(){
    const t = state.tutorial;
    const c = state.tutorialContent;
    if (t.result !== true || t.tutorialShown) return '';
    if (!c) return `<div class="tutorial-banner">Loading tutorial…</div>`;
    const ruleSecs = c.sections.map(s => `<div class="t-sec"><h3>${esc(s.heading)}</h3><p>${esc(s.body)}</p></div>`).join('');
    const menuSecs = (c.menuSections || []).map(s => `<div class="t-sec"><h3>${esc(s.heading)}</h3><p>${esc(s.body)}</p></div>`).join('');
    return `<div class="tutorial-card"><h2>${esc(c.title)}</h2>${ruleSecs}${menuSecs ? `<div class="menu-label">Using this screen</div>${menuSecs}` : ''}<p class="wait">Waiting for the host to finish reading. They'll dismiss this when everyone is ready.</p></div>`;
  }

  function viewTutorialVote(){
    const t = state.tutorial;
    if (t.isOpen) {
      return `<div class="panel"><h2>Show tutorial first?</h2><p class="small">${t.yesCount + t.noCount} / ${t.eligibleCount} voted — majority wins.</p><div class="vote-row"><button class="vote-yes ${state.myTutorialVote===true?'selected':''}" id="tut-yes">Yes (${t.yesCount})</button><button class="vote-no ${state.myTutorialVote===false?'selected':''}" id="tut-no">No (${t.noCount})</button></div></div>`;
    }
    if (t.result === null && !t.tutorialShown) {
      return `<div class="panel"><p class="small">Want a refresher on the rules?</p><button id="call-tut">Call tutorial vote</button></div>`;
    }
    if (t.result === false) return `<div class="panel" style="text-align:center"><p class="small">Majority voted to skip the tutorial.</p></div>`;
    return '';
  }

  function bindTutorialVote(){
    const cb = document.getElementById('call-tut');
    if (cb) cb.addEventListener('click', () => send({type:'call_tutorial_vote'}));
    const y = document.getElementById('tut-yes'), n = document.getElementById('tut-no');
    if (y) y.addEventListener('click', () => { state.myTutorialVote=true; send({type:'tutorial_vote', yes:true}); render(); });
    if (n) n.addEventListener('click', () => { state.myTutorialVote=false; send({type:'tutorial_vote', yes:false}); render(); });
  }

  function renderTable(){
    const top = state.topCard;
    const isMyTurn = state.currentId === state.me.id;
    const myHand = state.hand;

    const playersBar = state.players.map(p =>
      `<div class="pchip ${state.currentId===p.id?'current':''}"><div class="name">${esc(p.name)}${state.me.id===p.id?' (you)':''}</div><div class="hc">${p.handCount} cards</div></div>`).join('');

    const topPile = top
      ? `<div class="pile discard ${suitIsRed(top.suit)?'red':''}"><div><div>${rankShort(top.rank)}</div><div style="font-size:24px">${suitGlyph(top.suit)}</div></div></div>`
      : '<div class="pile discard"></div>';

    const drawCanClick = isMyTurn && !state.justDrew && !state.pickingSuitFor;
    const handHtml = myHand.map(c => {
      const playable = isPlayable(c);
      const cls = ['card', suitIsRed(c.suit)?'red':'', !isMyTurn || !playable ? 'unplayable':'', state.picked && state.picked.suit===c.suit && state.picked.rank===c.rank ? 'selected':''].join(' ');
      return `<div class="${cls}" data-suit="${c.suit}" data-rank="${c.rank}"><div class="rank">${rankShort(c.rank)}</div><div class="suit">${suitGlyph(c.suit)}</div></div>`;
    }).join('');

    const passBtn = isMyTurn && state.justDrew
      ? '<button id="pass" class="gray" style="margin-top:8px">Pass</button>' : '';
    const playBtn = isMyTurn && state.picked
      ? `<button id="play" style="margin-top:8px">Play ${rankShort(state.picked.rank)}${suitGlyph(state.picked.suit)}</button>` : '';

    root.innerHTML = `
      <div class="players">${playersBar}</div>
      <div class="table">
        <div class="top">
          <div class="pile draw ${drawCanClick?'':'disabled'}" id="draw">${state.drawCount}<small>draw</small></div>
          ${topPile}
        </div>
        <div class="active-suit">Active suit: ${suitGlyph(state.activeSuit || (top && top.suit))}</div>
        <div class="turn-info">${isMyTurn ? '— Your turn —' : esc(currentName())+'’s turn'}</div>
        ${state.lastEvent ? `<div class="turn-info" style="opacity:.7">${esc(state.lastEvent)}</div>` : ''}
      </div>
      <div class="hand">${handHtml || '<p style="color:var(--muted);padding:12px">No cards</p>'}</div>
      ${playBtn}${passBtn}
      ${state.pickingSuitFor ? renderSuitPicker() : ''}
    `;

    bindTable();
  }

  function renderSuitPicker(){
    return `<div class="modal"><div class="panel"><h2>Declare a new suit</h2><div class="suit-picker">
      <button data-s="clubs">♣</button><button data-s="diamonds" style="color:#c62828">♦</button>
      <button data-s="hearts" style="color:#c62828">♥</button><button data-s="spades">♠</button>
    </div></div></div>`;
  }

  function renderOver(){
    const winner = state.players.find(p => p.id === state.winnerId);
    root.innerHTML = `<h1>Game over</h1><div class="panel"><p style="text-align:center;font-size:24px;font-weight:700">${esc(winner ? winner.name : '?')} wins!</p>${state.players.map(p=>`<div class="pchip" style="margin-bottom:6px"><div class="name">${esc(p.name)}${p.id===state.winnerId?' 🏆':''}</div><div class="hc">${p.handCount} cards left</div></div>`).join('')}<p style="text-align:center;color:var(--muted);margin-top:16px">Waiting for the host to start a new game…</p></div>`;
  }

  function bindTable(){
    document.querySelectorAll('.card').forEach(el => {
      el.addEventListener('click', () => {
        const c = { suit: el.dataset.suit, rank: parseInt(el.dataset.rank,10) };
        if (!isPlayable(c) || state.currentId !== state.me.id) return;
        if (c.rank === 8) {
          state.pickingSuitFor = c;
          render(); return;
        }
        state.picked = c;
        render();
      });
    });
    const playBtn = document.getElementById('play');
    if (playBtn) playBtn.addEventListener('click', () => {
      send({ type:'play', suit: state.picked.suit, rank: state.picked.rank });
      state.picked = null;
    });
    const passBtn = document.getElementById('pass');
    if (passBtn) passBtn.addEventListener('click', () => send({ type:'pass' }));
    const drawBtn = document.getElementById('draw');
    if (drawBtn && state.currentId === state.me.id && !state.justDrew && !state.pickingSuitFor) {
      drawBtn.addEventListener('click', () => send({ type:'draw' }));
    }
    document.querySelectorAll('.suit-picker button').forEach(b => {
      b.addEventListener('click', () => {
        const card = state.pickingSuitFor;
        const declared = b.dataset.s;
        send({ type:'play', suit: card.suit, rank: card.rank, declaredSuit: declared });
        state.pickingSuitFor = null; state.picked = null;
      });
    });
  }

  function isPlayable(c) {
    if (!state.topCard) return true;
    if (c.rank === 8) return true;
    const active = state.activeSuit || state.topCard.suit;
    return c.suit === active || c.rank === state.topCard.rank;
  }
  function currentName() { return (state.players.find(p => p.id === state.currentId) || {}).name || ''; }
  function rankShort(r) { return ({11:'J',12:'Q',13:'K',14:'A'}[r] || String(r)); }
  function suitGlyph(s) { return ({clubs:'♣',diamonds:'♦',hearts:'♥',spades:'♠'}[s] || ''); }
  function suitIsRed(s) { return s==='diamonds' || s==='hearts'; }
  function esc(s){ return String(s).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  render();
})();
</script>
</body>
</html>
''';
