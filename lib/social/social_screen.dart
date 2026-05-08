import 'package:flutter/material.dart';

class SocialScreen extends StatelessWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social')),
      body: const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Offline multiplayer not wired up yet.\n\n'
            'Pick a Flutter transport plugin (BLE, Nearby Connections, '
            'Wi-Fi Direct, hotspot+mDNS) and implement Transport in '
            'lib/social/transport.dart.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
