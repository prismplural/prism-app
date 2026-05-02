import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var appClipboardChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    appClipboardChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/app_clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    appClipboardChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "readImage":
        guard self?.isDefaultClipboard(call.arguments) == true else {
          result(nil)
          return
        }
        result(self?.readClipboardImageData().map { FlutterStandardTypedData(bytes: $0) })
      case "readImageUri":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func readClipboardImageData() -> Data? {
    let pasteboard = NSPasteboard.general
    if let pngData = pasteboard.data(forType: .png) {
      return pngData
    }
    if let jpegData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
      return jpegData
    }
    if let tiffData = pasteboard.data(forType: .tiff),
       let image = NSImage(data: tiffData) {
      return pngData(from: image)
    }
    if let image = NSImage(pasteboard: pasteboard) {
      return pngData(from: image)
    }
    return nil
  }

  private func isDefaultClipboard(_ arguments: Any?) -> Bool {
    let args = arguments as? [String: Any]
    return (args?["pasteboard"] as? String ?? "clipboard") == "clipboard"
  }

  private func pngData(from image: NSImage) -> Data? {
    guard
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff)
    else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}
