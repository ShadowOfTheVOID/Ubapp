import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'proximity.dart';
import 'tag_engine.dart';
import 'tag_session.dart';
import 'tag_variant.dart';

class TagScreen extends StatefulWidget {
  const TagScreen({
    super.key,
    required this.session,
    required this.peerNames,
    this.manualProximity,
  });

  final TagSession session;
  final Map<String, String> peerNames;

  /// If provided, exposes a debug "tag this peer" button so the round can be
  /// driven without real BLE.
  final ManualProximity? manualProximity;

  @override
  State<TagScreen> createState() => _TagScreenState();
}

class _TagScreenState extends State<TagScreen> {
  late StreamSubscription<TagState> _sub;
  TagState? _state;
  Timer? _ticker;
  PlayerStatus? _lastSelfStatus;

  @override
  void initState() {
    super.initState();
    _state = widget.session.engine.state;
    _lastSelfStatus = _selfStatus(_state);
    _sub = widget.session.onStateChange.listen((s) {
      final newStatus = _selfStatus(s);
      if (newStatus != _lastSelfStatus) {
        _onMyStatusChange(newStatus);
        _lastSelfStatus = newStatus;
      }
      setState(() => _state = s);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub.cancel();
    _ticker?.cancel();
    widget.session.dispose();
    super.dispose();
  }

  PlayerStatus? _selfStatus(TagState? s) =>
      s?.players[widget.session.selfId]?.status;

  Future<void> _onMyStatusChange(PlayerStatus? next) async {
    if (next == PlayerStatus.it) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 80, 80, 80]);
      }
    } else if (next == PlayerStatus.frozen) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 200);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final me = state.players[widget.session.selfId];
    final variant = state.variant;
    final hideRole = variant.hidesIt && me?.status != PlayerStatus.it;
    final myStatus = me?.status ?? PlayerStatus.runner;

    final remainingMs = state.deadlineMs - DateTime.now().millisecondsSinceEpoch;
    final remaining = Duration(milliseconds: remainingMs.clamp(0, 1 << 31));

    return Scaffold(
      backgroundColor: _bgColor(myStatus, variant, hideRole),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(variant.displayName),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _RoleHeadline(
              status: myStatus,
              variant: variant,
              hideRole: hideRole,
              isOver: state.isOver,
              winnerName: state.winnerId == null
                  ? null
                  : state.players[state.winnerId]?.displayName,
              endReason: state.endReason,
            ),
            const SizedBox(height: 24),
            if (!state.isOver)
              Text(_formatDuration(remaining),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
            const Spacer(),
            _PeerStrip(state: state, selfId: widget.session.selfId),
            const SizedBox(height: 16),
            if (widget.manualProximity != null && !state.isOver)
              _DebugTagBar(
                state: state,
                selfId: widget.session.selfId,
                onTap: (peerId) =>
                    widget.manualProximity!.push(peerId),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _bgColor(PlayerStatus s, TagVariant v, bool hide) {
    if (hide) return Colors.indigo.shade900;
    return switch (s) {
      PlayerStatus.it => Colors.red.shade800,
      PlayerStatus.frozen => Colors.lightBlue.shade700,
      PlayerStatus.eliminated => Colors.grey.shade800,
      PlayerStatus.runner => Colors.green.shade700,
    };
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _RoleHeadline extends StatelessWidget {
  const _RoleHeadline({
    required this.status,
    required this.variant,
    required this.hideRole,
    required this.isOver,
    required this.winnerName,
    required this.endReason,
  });

  final PlayerStatus status;
  final TagVariant variant;
  final bool hideRole;
  final bool isOver;
  final String? winnerName;
  final String? endReason;

  @override
  Widget build(BuildContext context) {
    if (isOver) {
      final label = switch (endReason) {
        'all_frozen' => 'Everyone frozen',
        'last_survivor' => 'Last survivor',
        'hot_potato_timeout' => 'Time ran out',
        _ => 'Round over',
      };
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              winnerName == null ? 'Draw' : '$winnerName wins',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (hideRole) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Stay alert.\nThe bomb is hidden.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700),
        ),
      );
    }

    final (label, sub) = switch (status) {
      PlayerStatus.it => ('YOU\'RE IT', 'Tag someone — fast.'),
      PlayerStatus.runner => ('RUN', _runnerHint(variant)),
      PlayerStatus.frozen =>
        ('FROZEN', 'Wait for a teammate to unfreeze you.'),
      PlayerStatus.eliminated => ('OUT', 'Watch the rest play.'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2)),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  String _runnerHint(TagVariant v) => switch (v) {
        TagVariant.classic => 'Avoid the tagger.',
        TagVariant.freeze => 'Avoid the tagger. Unfreeze frozen friends.',
        TagVariant.zombie => 'Stay uninfected.',
        TagVariant.hotPotato => 'Don\'t end up holding the potato.',
        TagVariant.bomb => 'Avoid whoever might be it.',
      };
}

class _PeerStrip extends StatelessWidget {
  const _PeerStrip({required this.state, required this.selfId});
  final TagState state;
  final String selfId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: state.players.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = state.players.values.elementAt(i);
          final showStatus = !state.variant.hidesIt || p.id == selfId;
          return Container(
            width: 76,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: _avatarColor(p.status, showStatus),
                  child: Text(p.displayName.isEmpty
                      ? '?'
                      : p.displayName[0].toUpperCase()),
                ),
                const SizedBox(height: 6),
                Text(
                  p.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showStatus)
                  Text(_statusLabel(p.status),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10)),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _avatarColor(PlayerStatus s, bool reveal) {
    if (!reveal) return Colors.white24;
    return switch (s) {
      PlayerStatus.it => Colors.redAccent,
      PlayerStatus.frozen => Colors.lightBlueAccent,
      PlayerStatus.eliminated => Colors.grey,
      PlayerStatus.runner => Colors.greenAccent,
    };
  }

  String _statusLabel(PlayerStatus s) => switch (s) {
        PlayerStatus.it => 'IT',
        PlayerStatus.frozen => 'frozen',
        PlayerStatus.eliminated => 'out',
        PlayerStatus.runner => '',
      };
}

class _DebugTagBar extends StatelessWidget {
  const _DebugTagBar({
    required this.state,
    required this.selfId,
    required this.onTap,
  });

  final TagState state;
  final String selfId;
  final void Function(String peerId) onTap;

  @override
  Widget build(BuildContext context) {
    final me = state.players[selfId];
    if (me == null) return const SizedBox.shrink();

    final reachable = state.players.values
        .where((p) => p.id != selfId)
        .where((p) => switch (state.variant) {
              TagVariant.freeze => me.status == PlayerStatus.it
                  ? p.status == PlayerStatus.runner
                  : p.status == PlayerStatus.frozen,
              _ => p.status == PlayerStatus.runner,
            })
        .toList();

    if (reachable.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: [
          for (final p in reachable)
            ActionChip(
              label: Text('Touch ${p.displayName}'),
              avatar: const Icon(Icons.touch_app, size: 18),
              onPressed: () => onTap(p.id),
            ),
        ],
      ),
    );
  }
}
