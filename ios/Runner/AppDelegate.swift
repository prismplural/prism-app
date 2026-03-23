import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenshotEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenshotDetected),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenshotDetector") else { return }
    FlutterEventChannel(
      name: "com.prism.prism_plurality/screenshot_events",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(self)
  }

  @objc private func screenshotDetected() {
    screenshotEventSink?(nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    screenshotEventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    screenshotEventSink = nil
    return nil
  }
}
