import 'package:flutter/material.dart';

import '../games/codenames/codenames_screen.dart';
import '../games/crazy_eights/crazy_eights_screen.dart';
import '../games/imposter/imposter_screen.dart';
import '../games/mafia/mafia_screen.dart';
import '../games/tag/tag_lobby_screen.dart';
import '../realtime/real_time_screen.dart';
import '../social/social_screen.dart';
import '../turnbased/connect_four_screen.dart';
import '../turnbased/turn_based_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ubapp')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuButton(
                label: 'Mafia',
                onTap: () => _push(context, const MafiaScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Imposter',
                onTap: () => _push(context, const ImposterScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Codenames',
                onTap: () => _push(context, const CodenamesScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Crazy Eights',
                onTap: () => _push(context, const CrazyEightsScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Tag (BLE proximity)',
                onTap: () => _push(context, const TagLobbyScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Real-time',
                onTap: () => _push(context, const RealTimeScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Turn-based (tic-tac-toe)',
                onTap: () => _push(context, const TurnBasedScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Connect Four',
                onTap: () => _push(context, const ConnectFourScreen()),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Social',
                onTap: () => _push(context, const SocialScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          textStyle: const TextStyle(fontSize: 18),
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
