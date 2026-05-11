import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../social/host_server.dart';
import 'tag_protocol.dart';

/// Bidirectional channel for tag messages. The host wraps its in-app
/// `HostServer` (fan-out to all connected app peers). Each peer wraps a
/// single outbound WebSocket to the host.
abstract class TagTransport {
  /// Outbound: send to everyone (host) or to the host (peer).
  void send(TagMessage msg);

  /// Inbound: TagMessages decoded from the wire.
  Stream<TagMessage> get inbound;

  /// Optional: who just connected. Host emits one event per app-peer
  /// WebSocket join. Peer transport never emits.
  Stream<String> get onPeerConnected;

  /// Optional: who just disconnected. Mirror of onPeerConnected.
  Stream<String> get onPeerDisconnected;

  Future<void> dispose();
}

/// Host-side: wraps a running HostServer. All inbound guest messages are
/// parsed as TagMessages; `send` broadcasts to every connected guest.
/// Owns the server — `dispose()` stops it.
class HostTagTransport implements TagTransport {
  HostTagTransport(this._server) {
    _msgSub = _server.onGuestMessage.listen(_onGuestMessage);
    _joinSub = _server.onGuestJoin.listen((g) => _onConnect.add(g.value));
    _leaveSub = _server.onGuestLeave.listen((g) {
      final pid = _guestToPeer.remove(g);
      if (pid != null) _onDisconnect.add(pid);
    });
  }

  final HostServer _server;
  final _inbound = StreamController<TagMessage>.broadcast();
  final _onConnect = StreamController<String>.broadcast();
  final _onDisconnect = StreamController<String>.broadcast();
  final Map<GuestId, String> _guestToPeer = {};

  StreamSubscription? _msgSub;
  StreamSubscription? _joinSub;
  StreamSubscription? _leaveSub;

  void _onGuestMessage(GuestMessage m) {
    try {
      final msg = TagMessage.decode(m.payload);
      if (msg is HelloMessage) {
        _guestToPeer[m.from] = msg.peerId;
      }
      _inbound.add(msg);
      // Echo non-start traffic back so other peers see it. Host's
      // TagSession already applied any state change locally.
      if (msg is! HelloMessage) {
        _server.broadcast(m.payload);
      }
    } catch (_) {
      // ignore malformed payloads
    }
  }

  @override
  void send(TagMessage msg) => _server.broadcast(msg.encode());

  @override
  Stream<TagMessage> get inbound => _inbound.stream;
  @override
  Stream<String> get onPeerConnected => _onConnect.stream;
  @override
  Stream<String> get onPeerDisconnected => _onDisconnect.stream;

  @override
  Future<void> dispose() async {
    await _msgSub?.cancel();
    await _joinSub?.cancel();
    await _leaveSub?.cancel();
    await _server.stop();
    await _inbound.close();
    await _onConnect.close();
    await _onDisconnect.close();
  }
}

/// Peer-side: connects one WebSocket to the host. Everything `send`-ed
/// goes to the host, which fans out to all peers (including us). Inbound
/// stream surfaces the fanned-out copies.
class PeerTagTransport implements TagTransport {
  PeerTagTransport(this._channel) {
    _sub = _channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            _inbound.add(TagMessage.decode(data));
          } catch (_) {
            // skip
          }
        }
      },
      onError: (_) {},
      onDone: () {},
      cancelOnError: false,
    );
  }

  factory PeerTagTransport.connect(Uri serverUri) {
    final wsUri = serverUri.replace(
      scheme: serverUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
    );
    return PeerTagTransport(WebSocketChannel.connect(wsUri));
  }

  final WebSocketChannel _channel;
  late final StreamSubscription _sub;
  final _inbound = StreamController<TagMessage>.broadcast();

  @override
  void send(TagMessage msg) => _channel.sink.add(msg.encode());

  @override
  Stream<TagMessage> get inbound => _inbound.stream;

  @override
  Stream<String> get onPeerConnected => const Stream<String>.empty();
  @override
  Stream<String> get onPeerDisconnected => const Stream<String>.empty();

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    await _channel.sink.close();
    await _inbound.close();
  }
}

/// Local-only transport. Used when there's no network (single-device dev
/// mode). Messages echo back into [inbound] so the engine still sees
/// what it sent.
class LoopbackTagTransport implements TagTransport {
  final _inbound = StreamController<TagMessage>.broadcast();
  @override
  void send(TagMessage msg) => _inbound.add(msg);
  @override
  Stream<TagMessage> get inbound => _inbound.stream;
  @override
  Stream<String> get onPeerConnected => const Stream<String>.empty();
  @override
  Stream<String> get onPeerDisconnected => const Stream<String>.empty();
  @override
  Future<void> dispose() async => _inbound.close();
}
