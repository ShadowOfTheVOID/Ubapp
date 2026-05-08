import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One-tap host server. Spins up:
///   - HTTP on /              → tiny landing page for browser guests
///   - WebSocket on /ws       → bidirectional channel per guest
///
/// Messages are line-oriented JSON. Whatever's sent in by any guest is
/// fanned out via [onGuestMessage]; whatever the host sends via [broadcast]
/// goes to all guests.
class HostServer {
  HostServer({this.port = 7654});

  final int port;
  HttpServer? _server;
  final _guests = <WebSocketChannel>{};
  final _onMessage = StreamController<HostMessage>.broadcast();

  String? hostIp;
  int? hostPort;

  Stream<HostMessage> get onGuestMessage => _onMessage.stream;
  int get guestCount => _guests.length;

  Future<Uri?> start() async {
    final ip = await NetworkInfo().getWifiIP();
    if (ip == null) return null;

    final wsHandler = webSocketHandler((WebSocketChannel ws, _) {
      _guests.add(ws);
      ws.stream.listen(
        (raw) {
          if (raw is String) {
            _onMessage.add(HostMessage(channel: ws, payload: raw));
          }
        },
        onDone: () => _guests.remove(ws),
        onError: (_) => _guests.remove(ws),
        cancelOnError: true,
      );
    });

    final router = (Request req) {
      if (req.url.path == 'ws') return wsHandler(req);
      return Response.ok(_landingHtml, headers: {'content-type': 'text/html'});
    };

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
    hostIp = ip;
    hostPort = _server!.port;
    return Uri(scheme: 'http', host: ip, port: _server!.port);
  }

  void broadcast(String payload) {
    for (final g in _guests.toList()) {
      try {
        g.sink.add(payload);
      } catch (_) {
        _guests.remove(g);
      }
    }
  }

  Future<void> stop() async {
    for (final g in _guests) {
      await g.sink.close();
    }
    _guests.clear();
    await _server?.close(force: true);
    _server = null;
    await _onMessage.close();
  }
}

class HostMessage {
  HostMessage({required this.channel, required this.payload});
  final WebSocketChannel channel;
  final String payload;

  Map<String, Object?> get asJson =>
      jsonDecode(payload) as Map<String, Object?>;
}

const _landingHtml = '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Ubapp guest</title>
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; background:#0d1117; color:#e6edf3; margin:0; padding:24px; }
    h1 { font-size: 22px; margin-top: 0; }
    .card { background:#161b22; padding:20px; border-radius:14px; max-width:480px; margin:auto; }
    .badge { display:inline-block; padding:2px 8px; border-radius:8px; background:#1f6feb; color:#fff; font-size:12px; }
  </style>
</head>
<body>
  <div class="card">
    <span class="badge">connected</span>
    <h1>You're in.</h1>
    <p>Waiting for the host to start a game…</p>
    <p style="opacity:.7;font-size:13px">Tag isn't browser-playable (it needs Bluetooth). When the host starts a card, social, or trivia game, this page will switch to it.</p>
  </div>
  <script>
    const ws = new WebSocket(`ws://\${location.host}/ws`);
    ws.addEventListener('open', () => ws.send(JSON.stringify({type:'hello', via:'browser'})));
    ws.addEventListener('message', e => console.log('host:', e.data));
  </script>
</body>
</html>
''';
