import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../native/ble_advertiser.dart';
import '../../social/host_server.dart';
import 'ble_runtime.dart';
import 'proximity.dart';
import 'tag_protocol.dart';
import 'tag_screen.dart';
import 'tag_session.dart';
import 'tag_transport.dart';
import 'tag_variant.dart';

enum _Mode { idle, hosting, joining, joined }

class TagLobbyScreen extends StatefulWidget {
  const TagLobbyScreen({super.key});

  @override
  State<TagLobbyScreen> createState() => _TagLobbyScreenState();
}

class _TagLobbyScreenState extends State<TagLobbyScreen> {
  TagVariant _variant = TagVariant.classic;
  _Mode _mode = _Mode.idle;
  bool _useRealBle = false;
  bool? _bleAvailable;

  // Host state.
  HostServer? _server;
  HostTagTransport? _hostTransport;
  Uri? _serverUri;
  StreamSubscription? _hostHelloSub;
  String _selfId = 'host-${_id()}';
  String _selfName = 'Host';
  final Map<String, String> _peers = {}; // id -> displayName, includes host

  // Peer state.
  PeerTagTransport? _peerTransport;
  StreamSubscription? _peerInboundSub;
  final _hostUrlController = TextEditingController(text: 'http://192.168.1.1:7654');
  String _peerStatus = '';
  bool _peerWaitingStart = false;

  @override
  void initState() {
    super.initState();
    _peers[_selfId] = _selfName;
    BleAdvertiser.instance.isAvailable().then((b) {
      if (mounted) setState(() => _bleAvailable = b);
    });
  }

  @override
  void dispose() {
    _hostHelloSub?.cancel();
    _hostTransport?.dispose();
    _server?.stop();
    _peerInboundSub?.cancel();
    _peerTransport?.dispose();
    _hostUrlController.dispose();
    super.dispose();
  }

  String _id() => Random().nextInt(0xffff).toRadixString(16);

  Future<void> _startHosting() async {
    setState(() => _mode = _Mode.hosting);
    final server = HostServer();
    final uri = await server.start();
    final transport = HostTagTransport(server);

    _hostHelloSub = transport.inbound.listen((msg) {
      if (msg is HelloMessage) {
        setState(() => _peers[msg.peerId] = msg.displayName);
      }
    });
    transport.onPeerDisconnected.listen((peerId) {
      if (mounted && _mode == _Mode.hosting) {
        setState(() => _peers.remove(peerId));
      }
    });

    setState(() {
      _server = server;
      _serverUri = uri;
      _hostTransport = transport;
    });
  }

  Future<void> _stopHosting() async {
    await _hostHelloSub?.cancel();
    _hostHelloSub = null;
    await _hostTransport?.dispose();
    _hostTransport = null;
    await _server?.stop();
    setState(() {
      _server = null;
      _serverUri = null;
      _mode = _Mode.idle;
      _peers
        ..clear()
        ..[_selfId] = _selfName;
    });
  }

  Future<void> _joinHost() async {
    final url = _hostUrlController.text.trim();
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      setState(() {
        _mode = _Mode.joining;
        _peerStatus = 'Connecting to $url…';
      });
      final transport = PeerTagTransport.connect(uri);
      _peerInboundSub = transport.inbound.listen(_onPeerInbound);
      transport.send(HelloMessage(peerId: _selfId, displayName: _selfName));
      setState(() {
        _peerTransport = transport;
        _mode = _Mode.joined;
        _peerStatus = 'Joined. Waiting for the host to start…';
        _peerWaitingStart = true;
      });
    } catch (e) {
      setState(() {
        _mode = _Mode.idle;
        _peerStatus = 'Connection failed: $e';
      });
    }
  }

  Future<void> _leaveHost() async {
    await _peerInboundSub?.cancel();
    _peerInboundSub = null;
    await _peerTransport?.dispose();
    _peerTransport = null;
    setState(() {
      _mode = _Mode.idle;
      _peerWaitingStart = false;
      _peerStatus = '';
    });
  }

  void _onPeerInbound(TagMessage msg) {
    if (msg is StartMessage && _peerWaitingStart && mounted) {
      _peerWaitingStart = false;
      _enterRoundAsPeer(msg);
    }
  }

  /// Host: build the TagSession and push to TagScreen. The transport stays
  /// owned by the session; we null it out here so dispose doesn't double-close.
  Future<void> _startRoundAsHost() async {
    if (_hostTransport == null) return;
    if (_peers.length < 2) return;

    final (proximity, manualProximity) = _makeProximity();
    final transport = _hostTransport!;
    final session = TagSession(
      selfId: _selfId,
      selfDisplayName: _selfName,
      proximity: proximity,
      transport: transport,
    );

    // Hand the transport (and the HostServer it owns) off to the session.
    // Null out both refs so the lobby's dispose doesn't double-close.
    _hostTransport = null;
    _server = null;
    await _hostHelloSub?.cancel();
    _hostHelloSub = null;

    await session.startHosting(variant: _variant, peerNames: _peers);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TagScreen(
        session: session,
        manualProximity: manualProximity,
        peerNames: _peers,
      ),
    )).then((_) {
      // Round ended; back in the lobby. Host server is also gone (session
      // owned the transport which closed the server).
      if (mounted) {
        setState(() {
          _server = null;
          _serverUri = null;
          _mode = _Mode.idle;
          _peers
            ..clear()
            ..[_selfId] = _selfName;
        });
      }
    });
  }

  Future<void> _enterRoundAsPeer(StartMessage start) async {
    final transport = _peerTransport;
    if (transport == null) return;

    final (proximity, manualProximity) = _makeProximity();
    final session = TagSession(
      selfId: _selfId,
      selfDisplayName: _selfName,
      proximity: proximity,
      transport: transport,
    );

    // Hand off. The session has already subscribed to inbound and will
    // pick up the StartMessage on its own from the broadcast stream — but
    // we may have consumed it on the lobby subscription, so apply it
    // directly to be sure.
    _peerTransport = null;
    await _peerInboundSub?.cancel();
    _peerInboundSub = null;

    // Re-feed the start message so the session's _handleIncoming fires.
    // Easier: bypass and call its public startHosting? No — peer didn't
    // host. Use a tiny shim: synthesize the round directly.
    session.engine.start(start, start.peerNames);
    await proximity.start();

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TagScreen(
        session: session,
        manualProximity: manualProximity,
        peerNames: start.peerNames,
      ),
    )).then((_) {
      if (mounted) {
        setState(() {
          _mode = _Mode.idle;
          _peerStatus = '';
          _peerWaitingStart = false;
        });
      }
    });
  }

  (ProximitySource, ManualProximity?) _makeProximity() {
    if (_useRealBle && (_bleAvailable ?? false)) {
      return (BleProximityRuntime(selfPeerId: _selfId), null);
    }
    final m = ManualProximity();
    return (m, m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tag')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('Choose a variant'),
          const SizedBox(height: 12),
          ...TagVariant.values.map(
            (v) => _VariantCard(
              variant: v,
              selected: v == _variant,
              onTap: () => setState(() => _variant = v),
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle('Proximity source'),
          const SizedBox(height: 8),
          _BleToggle(
            available: _bleAvailable,
            value: _useRealBle,
            onChanged: (v) => setState(() => _useRealBle = v),
          ),
          const SizedBox(height: 24),
          if (_mode == _Mode.idle) _idleControls(),
          if (_mode == _Mode.hosting) _hostingPanel(),
          if (_mode == _Mode.joining || _mode == _Mode.joined) _peerPanel(),
        ],
      ),
    );
  }

  Widget _idleControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('Play'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _startHosting,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Host a game'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                Text('— or —',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _hostUrlController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Host URL',
                    hintText: 'http://192.168.1.5:7654',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _joinHost,
                  icon: const Icon(Icons.link),
                  label: const Text('Join a host'),
                ),
              ],
            ),
          ),
        ),
        if (_peerStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_peerStatus,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _hostingPanel() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_serverUri != null) _HostBadge(uri: _serverUri!),
            const SizedBox(height: 12),
            Text('Lobby (${_peers.length})',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._peers.entries.map(
              (e) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(e.value[0])),
                title: Text(e.value),
                subtitle: Text(e.key,
                    style: theme.textTheme.bodySmall),
                trailing: e.key == _selfId
                    ? const Chip(label: Text('You'))
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _peers.length >= 2 ? _startRoundAsHost : null,
              icon: const Icon(Icons.play_arrow),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _peers.length >= 2
                      ? 'Start ${_variant.displayName}'
                      : 'Need at least 2 players',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _stopHosting,
              child: const Text('Stop hosting'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _peerPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.link, size: 48),
            const SizedBox(height: 8),
            Text(_peerStatus,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _leaveHost,
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BleToggle extends StatelessWidget {
  const _BleToggle({
    required this.available,
    required this.value,
    required this.onChanged,
  });
  final bool? available;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bleReady = available == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use real BLE'),
              subtitle: Text(
                bleReady
                    ? 'Scan + advertise via flutter_blue_plus and the native BleAdvertiser plugin'
                    : (available == null
                        ? 'Checking BLE availability…'
                        : 'BLE advertiser plugin not installed — see tooling/ble_native/README.md'),
                style: theme.textTheme.bodySmall,
              ),
              value: value && bleReady,
              onChanged: bleReady ? onChanged : null,
            ),
            if (!bleReady)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Falls back to the manual test stream — "Touch player X" chips on the game screen drive proximity events.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final TagVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: variant.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(variant.icon, color: variant.accent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(variant.displayName,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(variant.tagline,
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HostBadge extends StatelessWidget {
  const _HostBadge({required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            color: Colors.white,
            child: QrImageView(data: uri.toString(), size: 96),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hosting', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(uri.toString(),
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  'Other phones join via the app — paste this URL into the Join field.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
