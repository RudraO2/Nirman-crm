// Story 3.6 — Firebase Cloud Messaging setup
// Handles token registration, foreground/background message routing,
// and notification-tap deep-link navigation to lead detail screen.
//
// Setup required (one-time):
//   1. Add google-services.json (Android) and GoogleService-Info.plist (iOS) to app.
//   2. Call NotificationsService.initialize() in main() after Firebase.initializeApp().
//   3. Set FCM_SERVICE_ACCOUNT secret in Supabase dashboard.

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
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

  /// Whether [enablePush] already ran this process (once per session is enough).
  static bool _pushEnabled = false;

  /// Cold-start wiring only — handlers and tap routing. Deliberately does NOT
  /// ask for the notification permission: a system dialog on the login screen,
  /// before the user knows what the app is, is when people tap Deny (eyeball
  /// review 2026-07-12). The ask moved to [enablePush], post-login.
  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // App opened from terminated state via notification tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessageTap(initial);

    // App opened from background state via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  /// Ask for the notification permission + register the FCM token. Call once
  /// the user is signed in (the token upsert RPC needs their session anyway,
  /// so pre-login registration was silently failing on every cold start).
  /// Safe to call repeatedly; no-ops after the first success and when
  /// Firebase itself failed to initialize.
  static Future<void> enablePush() async {
    if (_pushEnabled || Firebase.apps.isEmpty) return;
    _pushEnabled = true;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await _registerToken();
      FirebaseMessaging.instance.onTokenRefresh.listen(_upsertToken);
    } catch (_) {
      // Best-effort — pushes are an enhancement, never a blocker.
    }
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
    // A specific lead wins; otherwise honour an explicit route (e.g. streak-at-risk → /home).
    final leadId = message.data['lead_id'] as String?;
    final route = message.data['route'] as String?;
    if (leadId != null && leadId.isNotEmpty) {
      appRouter.go('/lead/$leadId');
    } else if (route != null && route.isNotEmpty) {
      appRouter.go(route);
    }
  }

  static String _platform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
