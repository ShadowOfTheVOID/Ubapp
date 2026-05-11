import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Identifies one connected guest (browser tab or app instance) for the
/// duration of the connection. Stable across messages from the same socket.
class GuestId {
  const GuestId(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is GuestId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

class GuestMessage {
  GuestMessage({required this.from, required this.payload});
  final GuestId from;
  final String payload;

  Map<String, Object?> get asJson =>
      jsonDecode(payload) as Map<String, Object?>;
}

/// One-tap host server. Spins up:
///   - HTTP on /              → game-supplied landing HTML
///   - WebSocket on /ws       → bidirectional channel per guest
///
/// Game adapters consume [onGuestMessage], [send] privately to one guest, or
/// [broadcast] to all. The served HTML can be swapped by setting [html]
/// before [start] (or the default lobby placeholder is used).
class HostServer {
  HostServer({this.port = 7654, String? html})
      : _html = html ?? _defaultHtml;

  final int port;
  String _html;
  set html(String value) => _html = value;

  HttpServer? _server;
  final _byId = <GuestId, WebSocketChannel>{};
  int _nextId = 0;
  final _onMessage = StreamController<GuestMessage>.broadcast();
  final _onJoin = StreamController<GuestId>.broadcast();
  final _onLeave = StreamController<GuestId>.broadcast();

  String? hostIp;
  int? hostPort;

  Stream<GuestMessage> get onGuestMessage => _onMessage.stream;
  Stream<GuestId> get onGuestJoin => _onJoin.stream;
  Stream<GuestId> get onGuestLeave => _onLeave.stream;
  int get guestCount => _byId.length;
  Iterable<GuestId> get guests => _byId.keys;

  Future<Uri?> start() async {
    final ip = await NetworkInfo().getWifiIP();

    final wsHandler = webSocketHandler((WebSocketChannel ws, _) {
      final id = GuestId('g${_nextId++}');
      _byId[id] = ws;
      _onJoin.add(id);
      ws.stream.listen(
        (raw) {
          if (raw is String) {
            _onMessage.add(GuestMessage(from: id, payload: raw));
          }
        },
        onDone: () {
          _byId.remove(id);
          _onLeave.add(id);
        },
        onError: (_) {
          _byId.remove(id);
          _onLeave.add(id);
        },
        cancelOnError: true,
      );
    });

    Future<Response> router(Request req) async {
      if (req.url.path == 'ws') {
        return await wsHandler(req) as Response;
      }
      return Response.ok(_html, headers: {'content-type': 'text/html'});
    }

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
    hostIp = ip;
    hostPort = _server!.port;
    return ip == null
        ? null
        : Uri(scheme: 'http', host: ip, port: _server!.port);
  }

  void send(GuestId to, String payload) {
    final ws = _byId[to];
    if (ws == null) return;
    try {
      ws.sink.add(payload);
    } catch (_) {
      _byId.remove(to);
    }
  }

  void broadcast(String payload) {
    for (final id in _byId.keys.toList()) {
      send(id, payload);
    }
  }

  bool _stopped = false;

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final ws in _byId.values) {
      await ws.sink.close();
    }
    _byId.clear();
    await _server?.close(force: true);
    _server = null;
    if (!_onMessage.isClosed) await _onMessage.close();
    if (!_onJoin.isClosed) await _onJoin.close();
    if (!_onLeave.isClosed) await _onLeave.close();
  }
}

const _defaultHtml = '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Ubapp guest</title>
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; background:#0d1117; color:#e6edf3; margin:0; padding:24px; }
    .card { background:#161b22; padding:20px; border-radius:14px; max-width:480px; margin:auto; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Connected.</h1>
    <p>Waiting for the host to start a game…</p>
  </div>
</body>
</html>
''';
