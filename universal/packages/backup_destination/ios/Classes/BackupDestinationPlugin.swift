import Flutter
import UIKit
import UniformTypeIdentifiers

public class BackupDestinationPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pending: FlutterResult?
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BackupDestinationPlugin()
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "au.monster.tracker.plus/backup-destination", binaryMessenger: registrar.messenger()))
  }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "chooseFolder" {
      guard pending == nil, let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
        result(FlutterError(code: "PICKER_UNAVAILABLE", message: "Open settings before choosing a folder.", details: nil)); return
      }
      pending = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.delegate = self
      var presenter = root
      while let presented = presenter.presentedViewController { presenter = presented }
      presenter.present(picker, animated: true)
    } else if call.method == "writeBackup" {
      guard let args = call.arguments as? [String: Any], let bookmark = args["folder"] as? String, let name = args["name"] as? String, let data = args["bytes"] as? FlutterStandardTypedData, name.range(of: "^[A-Za-z0-9.-]{1,160}$", options: .regularExpression) != nil, let bookmarkData = Data(base64Encoded: bookmark) else {
        result(FlutterError(code: "INVALID_BACKUP", message: "Invalid backup destination.", details: nil)); return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          var stale = false
          let folder = try URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
          guard !stale, folder.startAccessingSecurityScopedResource() else { throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Select the backup folder again. Local recovery is retained."]) }
          defer { folder.stopAccessingSecurityScopedResource() }
          let file = folder.appendingPathComponent(name)
          try data.data.write(to: file, options: .atomic)
          guard try Data(contentsOf: file) == data.data else { try? FileManager.default.removeItem(at: file); throw NSError(domain: "Backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Provider readback failed. Local recovery is retained."]) }
          DispatchQueue.main.async { result(nil) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "BACKUP_COPY_FAILED", message: error.localizedDescription, details: nil)) } }
      }
    } else { result(FlutterMethodNotImplemented) }
  }
  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }; pending = nil
    guard let url = urls.first else { result(nil); return }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    do { result(try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString()) }
    catch { result(FlutterError(code: "FOLDER_PERMISSION", message: error.localizedDescription, details: nil)) }
  }
  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { pending?(nil); pending = nil }
}
