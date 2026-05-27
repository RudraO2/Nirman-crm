import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    } on MissingPluginException {
      // Non-implementing platform — best-effort.
    } on Exception catch (e) {
      debugPrint('[ScreenSecurityService] $method platform error: $e');
    }
  }
}
