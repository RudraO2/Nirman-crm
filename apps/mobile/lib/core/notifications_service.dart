// Story 3.6 — Firebase Cloud Messaging setup
// Handles token registration, foreground/background message routing,
// and notification-tap deep-link navigation to lead detail screen.
//
// Setup required (one-time):
//   1. Add google-services.json (Android) and GoogleService-Info.plist (iOS) to app.
//   2. Call NotificationsService.initialize() in main() after Firebase.initializeApp().
//   3. Set FCM_SERVICE_ACCOUNT secret in Supabase dashboard.

import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../router/app_router.dart';

// Top-level handler required by firebase_messaging for background messages.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Background: no UI to update. Navigation happens on tap via onMessageOpenedApp.
}

class NotificationsService {
  NotificationsService._();

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Request permissions (iOS / newer Android)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Register / refresh token
    await _registerToken();
    FirebaseMessaging.instance.onTokenRefresh.listen(_upsertToken);

    // App opened from terminated state via notification tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessageTap(initial);

    // App opened from background state via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  static Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _upsertToken(token);
    } catch (_) {
      // Silently skip — token will be registered on next launch.
    }
  }

  static Future<void> _upsertToken(String token) async {
    try {
      await Supabase.instance.client.rpc('upsert_fcm_token', params: {
        'p_token':    token,
        'p_platform': _platform(),
      });
    } catch (_) {}
  }

  static void _handleMessageTap(RemoteMessage message) {
    final leadId = message.data['lead_id'] as String?;
    if (leadId != null && leadId.isNotEmpty) {
      appRouter.go('/lead/$leadId');
    }
  }

  static String _platform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
