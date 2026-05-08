import 'dart:async';
import 'dart:typed_data';

class PeerId {
  const PeerId(this.raw);
  final String raw;

  @override
  bool operator ==(Object other) => other is PeerId && other.raw == raw;
  @override
  int get hashCode => raw.hashCode;
  @override
  String toString() => 'PeerId($raw)';
}

class TransportMessage {
  const TransportMessage(this.peer, this.payload);
  final PeerId peer;
  final Uint8List payload;
}

/// Slot for the offline multiplayer transport. Pick a Flutter plugin
/// (flutter_blue_plus / nearby_connections / flutter_p2p_connection / etc.)
/// and implement this; the game screens stay unchanged.
abstract class Transport {
  Stream<PeerId> get onPeerFound;
  Stream<TransportMessage> get onMessage;

  Future<void> start();
  Future<void> stop();

  Future<void> send(PeerId to, Uint8List payload);
  Future<void> broadcast(Uint8List payload);
}
