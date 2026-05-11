import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../native/ble_advertiser.dart';
import '../../social/host_server.dart';
import 'ble_runtime.dart';
import 'proximity.dart';
import 'tag_protocol.dart';
import 'tag_screen.dart';
import 'tag_session.dart';
import 'tag_variant.dart';

class TagLobbyScreen extends StatefulWidget {
  const TagLobbyScreen({super.key});

  @override
  State<TagLobbyScreen> createState() => _TagLobbyScreenState();
}

class _TagLobbyScreenState extends State<TagLobbyScreen> {
  TagVariant _variant = TagVariant.classic;
  HostServer? _server;
  Uri? _serverUri;
  bool _starting = false;
  bool _useRealBle = false;
  bool? _bleAvailable;

  // Demo lobby — when running in manual mode the host adds fake peers so
  // the engine is testable on one device. In real-BLE mode peer rows would
  // populate from scan results (left for follow-up wiring).
  final Map<String, String> _peers = {'me': 'You'};
  final _selfId = 'me';

  @override
  void initState() {
    super.initState();
    BleAdvertiser.instance.isAvailable().then((b) {
      if (mounted) setState(() => _bleAvailable = b);
    });
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  Future<void> _toggleHost() async {
    if (_server != null) {
      await _server!.stop();
      setState(() {
        _server = null;
        _serverUri = null;
      });
      return;
    }
    setState(() => _starting = true);
    final server = HostServer();
    final uri = await server.start();
    setState(() {
      _starting = false;
      _server = server;
      _serverUri = uri;
    });
  }

  void _addFakePeer() {
    final id = 'peer-${_peers.length}';
    final name = 'Player ${_peers.length}';
    setState(() => _peers[id] = name);
  }

  Future<void> _startRound() async {
    if (_peers.length < 2) return;

    ProximitySource proximity;
    ManualProximity? manualProximity;
    if (_useRealBle && (_bleAvailable ?? false)) {
      proximity = BleProximityRuntime(selfPeerId: _selfId);
    } else {
      manualProximity = ManualProximity();
      proximity = manualProximity;
    }

    final session = TagSession(
      selfId: _selfId,
      selfDisplayName: _peers[_selfId]!,
      proximity: proximity,
      broadcast: (msg) {
        // Real cross-device transport plugs in here. With the host server
        // running, the next BLE step is to send TagMessage.encode() over
        // its WebSocket fan-out so other phones see the same engine state.
        debugPrint('tag tx: ${msg.encode()}');
      },
    );
    await session.startHosting(variant: _variant, peerNames: _peers);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TagScreen(
        session: session,
        manualProximity: manualProximity,
        peerNames: _peers,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          _SectionTitle('Lobby'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _starting ? null : _toggleHost,
                          icon: Icon(_server == null
                              ? Icons.wifi_tethering
                              : Icons.stop_circle_outlined),
                          label: Text(_server == null
                              ? (_starting ? 'Starting…' : 'Host a session')
                              : 'Stop hosting'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _useRealBle ? null : _addFakePeer,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Add player'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_serverUri != null) _HostBadge(uri: _serverUri!),
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
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _useRealBle
                                  ? null
                                  : () =>
                                      setState(() => _peers.remove(e.key)),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: _peers.length >= 2 ? _startRound : null,
            icon: const Icon(Icons.play_arrow),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _peers.length >= 2
                    ? 'Start ${_variant.displayName}'
                    : 'Need at least 2 players',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
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
                  'Falling back to the manual test stream — "Touch player X" chips on the game screen drive proximity events.',
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
                  'Browser guests can scan for non-tag games. Tag itself needs the app.',
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
