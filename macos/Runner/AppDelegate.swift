import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingInitialPdfPath: String?
  private var intentChannel: FlutterMethodChannel?

  func attachIntentChannel(_ channel: FlutterMethodChannel) {
    intentChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      if call.method == "consumeInitialPdfPath" {
        let path = self.pendingInitialPdfPath
        self.pendingInitialPdfPath = nil
        result(path)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    return handleIncomingFilePath(filename)
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    var handled = false
    for path in filenames {
      if handleIncomingFilePath(path) {
        handled = true
      }
    }
    sender.reply(toOpenOrPrint: handled ? .success : .failure)
  }

  private func handleIncomingFilePath(_ path: String) -> Bool {
    guard !path.isEmpty,
          path.lowercased().hasSuffix(".pdf"),
          FileManager.default.fileExists(atPath: path) else {
      return false
    }
    if let channel = intentChannel {
      DispatchQueue.main.async {
        channel.invokeMethod("onOpenExternalPdf", arguments: path)
      }
    } else {
      pendingInitialPdfPath = path
    }
    return true
  }
}
