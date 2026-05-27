import 'package:flutter/services.dart';

/// Story 1.8 — FR-31: Android FLAG_SECURE + iOS app-switcher blur.
/// Employee role: full protection. Admin role: unrestricted.
class ScreenSecurityService {
  static const _channel = MethodChannel('com.nirmanmedia.crm/screen_security');

  /// Apply protection based on role. Call after login and on app restart
  /// when a session is already present.
  static Future<void> applyForRole(String role) async {
    if (role == 'employee') {
      await _invoke('enableSecureFlag'); // Android
      await _invoke('enableBlur');       // iOS
    } else {
      await _invoke('disableSecureFlag');
      await _invoke('disableBlur');
    }
  }

  /// Clear all protection. Call on sign-out.
  static Future<void> disable() async {
    await _invoke('disableSecureFlag');
    await _invoke('disableBlur');
  }

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // MissingPluginException on non-implementing platform — best-effort.
    }
  }
}
