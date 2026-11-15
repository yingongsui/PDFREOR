import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let maxClipboardImageBytes = 24 * 1024 * 1024

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 720, height: 520)
    if windowFrame.width < 1180 || windowFrame.height < 780 {
      let targetFrame = NSRect(
        x: windowFrame.origin.x,
        y: windowFrame.origin.y,
        width: max(windowFrame.width, 1180),
        height: max(windowFrame.height, 780)
      )
      self.setFrame(targetFrame, display: true)
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupPlatformChannels(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func setupPlatformChannels(messenger: FlutterBinaryMessenger) {
    let intentChannel = FlutterMethodChannel(
      name: "com.yin.pdfreor/intent",
      binaryMessenger: messenger
    )
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
      appDelegate.attachIntentChannel(intentChannel)
    }

    let desktopChannel = FlutterMethodChannel(
      name: "com.yin.pdfreor/stylus",
      binaryMessenger: messenger
    )
    desktopChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "openUrl":
        guard let args = call.arguments as? [String: Any],
              let rawUrl = args["url"] as? String,
              let url = URL(string: rawUrl) else {
          result(false)
          return
        }
        result(NSWorkspace.shared.open(url))
      case "openFile":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
          result(false)
          return
        }
        result(NSWorkspace.shared.open(URL(fileURLWithPath: path)))
      case "getClipboardImage":
        DispatchQueue.global(qos: .userInitiated).async {
          let data = Self.readClipboardImageBytes()
          DispatchQueue.main.async {
            if let data = data {
              result(FlutterStandardTypedData(bytes: data))
            } else {
              result(nil)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func readClipboardImageBytes() -> Data? {
    let pasteboard = NSPasteboard.general
    if let pngData = pasteboard.data(forType: .png),
       !pngData.isEmpty,
       pngData.count <= maxClipboardImageBytes {
      return pngData
    }

    guard let image = NSImage(pasteboard: pasteboard),
          let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData) else {
      return nil
    }

    if let pngData = rep.representation(using: .png, properties: [:]),
       !pngData.isEmpty,
       pngData.count <= maxClipboardImageBytes {
      return pngData
    }

    if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]),
       !jpegData.isEmpty,
       jpegData.count <= maxClipboardImageBytes {
      return jpegData
    }
    return nil
  }
}
