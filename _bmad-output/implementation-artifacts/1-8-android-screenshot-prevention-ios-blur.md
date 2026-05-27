---
story_key: 1-8-android-screenshot-prevention-ios-blur
epic: 1
story: 8
story_id: 1.8
baseline_commit: ca3a1462  # main HEAD after Story 1.7 merge
supabase_project_id: vhgruadourflpxuzuxfn
github_repo: https://github.com/RudraO2/Nirman-crm
---

# Story 1.8: Android screenshot prevention + iOS app-switcher blur

Status: review

## Story

As a security officer,
I want the Employee mobile app to block screenshots on Android and blur sensitive views in the iOS app switcher,
So that casual data leakage via screen capture is reduced.

## Acceptance Criteria

1. **AC-1 — Android FLAG_SECURE for Employee role.** When any screen of the app is in the foreground on an Android device and the signed-in role is `employee`, `FLAG_SECURE` is set on the activity window. Screenshot and screen-recording attempts produce a black/empty image.

2. **AC-2 — iOS app-switcher blur for Employee role.** When the app moves to background (user opens app switcher) on an iOS device and the signed-in role is `employee`, a `UIVisualEffectView` blur overlay covers the entire window. The app switcher shows the blurred snapshot, not actual lead data.

3. **AC-3 — Admin role unrestricted.** When the signed-in role is `admin`, FLAG_SECURE is NOT set (Android) and the blur overlay is NOT shown (iOS). Screenshots work normally.

4. **AC-4 — Security applied immediately after login.** Within the same call to `AuthRepository.login()`, after session is established, `ScreenSecurityService.applyForRole(role)` is called. No window in the post-login flow is unprotected.

5. **AC-5 — Security restored on app restart.** If a session already exists when `main()` runs (app restart / refresh token), `ScreenSecurityService.applyForRole(role)` is called before `runApp()` using the role from `session.user.appMetadata['role']`.

6. **AC-6 — Security cleared on sign-out.** `AuthRepository.signOut()` calls `ScreenSecurityService.disable()` before `_supabase.auth.signOut()`, ensuring FLAG_SECURE and blur are cleared for the next login session.

7. **AC-7 — Platform channel: single named channel.** Both Android and iOS register handlers on `com.nirmanmedia.crm/screen_security`. Android handles `enableSecureFlag` / `disableSecureFlag`; iOS handles `enableBlur` / `disableBlur`. Each platform returns `notImplemented` for the other's methods — caught silently in Dart.

## Tasks / Subtasks

- [x] **T-1 — Android: MainActivity.kt**
  - [x] T-1.1 Create `apps/mobile/android/app/src/main/kotlin/com/nirmanmedia/crm/MainActivity.kt`
  - [x] T-1.2 Extend `FlutterActivity`, register MethodChannel `com.nirmanmedia.crm/screen_security`
  - [x] T-1.3 `enableSecureFlag`: `window.addFlags(FLAG_SECURE)`
  - [x] T-1.4 `disableSecureFlag`: `window.clearFlags(FLAG_SECURE)`

- [x] **T-2 — iOS: AppDelegate.swift**
  - [x] T-2.1 Create `apps/mobile/ios/Runner/AppDelegate.swift`
  - [x] T-2.2 Register MethodChannel after `super.application(_:didFinishLaunchingWithOptions:)`
  - [x] T-2.3 `enableBlur`: set `blurEnabled = true`
  - [x] T-2.4 `disableBlur`: set `blurEnabled = false`, remove overlay
  - [x] T-2.5 `applicationWillResignActive`: if `blurEnabled`, add `UIVisualEffectView(style: .systemMaterial)`
  - [x] T-2.6 `applicationDidBecomeActive`: remove blur overlay unconditionally

- [x] **T-3 — Dart: ScreenSecurityService**
  - [x] T-3.1 Create `apps/mobile/lib/shared/services/screen_security_service.dart`
  - [x] T-3.2 `applyForRole(role)`: call both `enableSecureFlag` + `enableBlur` for employee; disable both for admin
  - [x] T-3.3 `disable()`: call both disable methods
  - [x] T-3.4 Catch all exceptions (MissingPluginException + PlatformException) silently

- [x] **T-4 — Wire into auth_repository.dart**
  - [x] T-4.1 Add import for `screen_security_service.dart`
  - [x] T-4.2 Call `await ScreenSecurityService.applyForRole(role)` after `recoverSession` in `login()`
  - [x] T-4.3 Call `await ScreenSecurityService.disable()` before `signOut()`

- [x] **T-5 — Wire into main.dart**
  - [x] T-5.1 After `Supabase.initialize()`, check `currentSession`
  - [x] T-5.2 If session exists, call `ScreenSecurityService.applyForRole(role)` from `appMetadata`

- [x] **T-6 — PR + status update**
  - [x] T-6.1 Create branch `feat/1.8-screenshot-prevention` from main
  - [x] T-6.2 Push all files
  - [x] T-6.3 Open PR against `main`
  - [x] T-6.4 Update `sprint-status.yaml`: `backlog → review`

## Dev Notes

### Platform channel name

All files use the same channel: `com.nirmanmedia.crm/screen_security`.

Android handles: `enableSecureFlag`, `disableSecureFlag` → returns `notImplemented` for blur methods.
IOS handles: `enableBlur`, `disableBlur` → returns `notImplemented` for secure-flag methods.
Dart catches all exceptions silently — no error surfaces to the user.

### Android: MainActivity.kt — full implementation

```kotlin
package com.nirmanmedia.crm

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.nirmanmedia.crm/screen_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSecureFlag" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disableSecureFlag" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

### iOS: AppDelegate.swift — full implementation

Requires iOS 16+ (matches `ios_minimum_version` in architecture). `UIBlurEffect(style: .systemMaterial)` available iOS 13+.

```swift
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private var blurEnabled = false
    private var blurView: UIVisualEffectView?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "com.nirmanmedia.crm/screen_security",
                binaryMessenger: controller.binaryMessenger
            )
            channel.setMethodCallHandler { [weak self] call, result in
                switch call.method {
                case "enableBlur":
                    self?.blurEnabled = true
                    result(nil)
                case "disableBlur":
                    self?.blurEnabled = false
                    self?.removeBlurOverlay()
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }
        return result
    }

    override func applicationWillResignActive(_ application: UIApplication) {
        if blurEnabled { addBlurOverlay() }
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        removeBlurOverlay()
    }

    private func addBlurOverlay() {
        guard let window = window, blurView == nil else { return }
        let blur = UIBlurEffect(style: .systemMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(view)
        blurView = view
    }

    private func removeBlurOverlay() {
        blurView?.removeFromSuperview()
        blurView = nil
    }
}
```

### Dart: ScreenSecurityService — full implementation

```dart
import 'package:flutter/services.dart';

class ScreenSecurityService {
  static const _channel = MethodChannel('com.nirmanmedia.crm/screen_security');

  static Future<void> applyForRole(String role) async {
    if (role == 'employee') {
      await _invoke('enableSecureFlag');
      await _invoke('enableBlur');
    } else {
      await _invoke('disableSecureFlag');
      await _invoke('disableBlur');
    }
  }

  static Future<void> disable() async {
    await _invoke('disableSecureFlag');
    await _invoke('disableBlur');
  }

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {}
  }
}
```

### auth_repository.dart changes

Added import: `import '../../../shared/services/screen_security_service.dart';`

In `login()` — after `recoverSession` succeeds:
```dart
await ScreenSecurityService.applyForRole(role);
```

In `signOut()` — before `_supabase.auth.signOut()`:
```dart
await ScreenSecurityService.disable();
```

### main.dart changes

Added import: `import 'shared/services/screen_security_service.dart';`

After `Supabase.initialize()`, before `runApp()`:
```dart
final existingSession = Supabase.instance.client.auth.currentSession;
if (existingSession != null) {
  final role = existingSession.user.appMetadata['role'] as String? ?? 'employee';
  await ScreenSecurityService.applyForRole(role);
}
```

### iOS AppDelegate.swift — if file already existed

If `ios/Runner/AppDelegate.swift` was committed before this story, merge the method channel setup and lifecycle overrides into the existing file rather than replacing it. The `GeneratedPluginRegistrant.register(with: self)` call must remain.

### No pubspec.yaml changes

No new Flutter package needed. Implementation uses Flutter's built-in `MethodChannel` (part of `flutter/services.dart`). No external dependency added.

### Manual verification steps

1. **Android employee login:** screenshot → black image. Admin login → screenshot works.
2. **iOS employee login:** background app → app switcher shows blur. Admin login → no blur.
3. **App restart with saved session:** re-open app as employee → FLAG_SECURE / blur immediately active before any screen renders.
4. **Sign out:** FLAG_SECURE cleared; next user (admin) can screenshot normally.

## Change Log

| Date | Commit | Author | Note |
|------|--------|--------|------|
| 2026-05-27 | feat/1.8-screenshot-prevention | Amelia / Claude | Implementation complete; PR open |
