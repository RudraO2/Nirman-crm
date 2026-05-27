import 'package:flutter/material.dart';

/// Placeholder home screen — implemented fully in Story 3.8 (Today's Actions widget).
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nirman CRM')),
      body: const Center(
        child: Text('Home — coming in Story 3.8'),
      ),
    );
  }
}
