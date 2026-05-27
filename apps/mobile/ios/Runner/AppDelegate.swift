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
        if blurEnabled {
            addBlurOverlay()
        }
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
