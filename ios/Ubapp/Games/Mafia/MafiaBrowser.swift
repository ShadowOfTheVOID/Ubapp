import Foundation

/// HTML/CSS/JS served at `/` to browser-tier guests. The browser bundle and
/// the SwiftUI host view consume the same JSON the [MafiaServer] emits — when
/// adding a message type, add a handler on both sides.
///
/// TODO: Port the full lobby → night → day → reveal → game-over flow from
/// lib/games/mafia/mafia_browser.dart (584 lines). This placeholder only
/// covers the join handshake and a generic event log.
enum MafiaBrowser {
    static let html = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Mafia</title>
      <style>
        body { font-family: -apple-system, system-ui, sans-serif; background:#0d1117; color:#e6edf3; margin:0; padding:24px; }
        .card { background:#161b22; padding:20px; border-radius:14px; max-width:480px; margin:auto; }
        input, button { font-size:16px; padding:10px; border-radius:8px; border:none; }
        button { background:#238636; color:#fff; cursor:pointer; }
        #log p { margin: 4px 0; font-size: 14px; color: #8b949e; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>Mafia</h1>
        <div id="join">
          <input id="name" placeholder="Your name"><button onclick="join()">Join</button>
        </div>
        <div id="me" style="display:none"></div>
        <div id="log"></div>
      </div>
      <script>
        const ws = new WebSocket(`ws://${location.host}/ws`);
        let me = null;
        function log(t) { const p=document.createElement('p'); p.textContent=t; document.getElementById('log').appendChild(p); }
        function send(o) { ws.send(JSON.stringify(o)); }
        function join() {
          const n = document.getElementById('name').value.trim();
          if (!n) return;
          send({type:'join', name:n});
        }
        ws.onmessage = (e) => {
          const m = JSON.parse(e.data);
          switch (m.type) {
            case 'welcome':
              me = m.yourId;
              document.getElementById('join').style.display='none';
              document.getElementById('me').style.display='block';
              document.getElementById('me').textContent = `You are ${m.yourName}.`;
              break;
            case 'role':
              log(`Your role: ${m.role}` + (m.mafiaIds ? ` — mafia: ${m.mafiaIds.join(', ')}` : ''));
              break;
            default:
              log(JSON.stringify(m));
          }
        };
      </script>
    </body>
    </html>
    """
}
