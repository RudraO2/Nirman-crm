import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkPrimary),
        title: Text(
          'Settings',
          style: AppType.display(
            fontSize: 21, fontWeight: FontWeight.w500, color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.chevron_right),
            // Query param survives OS-triggered route restoration; in-memory extra does not.
            onTap: () => context.go('/password-change?forced=false'),
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Follow-up Alarms'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/alarms'),
          ),
        ],
      ),
    );
  }
}
