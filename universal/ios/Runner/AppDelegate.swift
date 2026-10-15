import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var sheetsPicker: SheetsPicker?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "SheetsPicker") { sheetsPicker = SheetsPicker(messenger: registrar.messenger()) }
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "au.monster.tracker.plus.sync", frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "au.monster.tracker.plus.backup", frequency: NSNumber(value: 24 * 60 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

import AuthenticationServices
import CryptoKit
import Security

/// Google's mobile Picker runs in the system authentication browser.
/// PKCE/state bind the code to this request; access tokens remain in memory.
private final class SheetsPicker: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?
  private var pending: FlutterResult?
  private var pendingID: UUID?
  private var timeout: Timer?
  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let channel = FlutterMethodChannel(name: "au.monster.tracker.plus/sheets-picker", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pick" else { result(FlutterMethodNotImplemented); return }
      self?.pick(call.arguments as? [String: Any] ?? [:], result: result)
    }
  }
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    return windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
  }
  private func finish(_ value: Any?, id: UUID) {
    DispatchQueue.main.async {
      guard self.pendingID == id else { return }
      self.pendingID = nil
      let result = self.pending
      self.pending = nil
      self.timeout?.invalidate(); self.timeout = nil
      self.session = nil
      result?(value)
    }
  }
  private func fail(_ message: String, id: UUID) {
    finish(FlutterError(code: "PICKER_FAILED", message: message, details: nil), id: id)
  }
  private func pick(_ args: [String: Any], result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "PICKER_BUSY", message: "Spreadsheet selection is already open.", details: nil)); return }
    guard let client = args["clientId"] as? String, client.hasSuffix(".apps.googleusercontent.com"), let email = args["email"] as? String, !email.isEmpty else {
      result(FlutterError(code: "SETUP_REQUIRED", message: "Configure the iOS Google client ID and reconnect your Google account.", details: nil)); return
    }
    var random = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
      result(FlutterError(code: "PICKER_FAILED", message: "Could not start secure authorization. Retry.", details: nil)); return
    }
    let verifier = Data(random).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    let state = UUID().uuidString
    let scheme = client.split(separator: ".").reversed().joined(separator: ".")
    let redirect = "\(scheme):/oauthredirect"
    var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    url.queryItems = ["client_id": client, "redirect_uri": redirect, "response_type": "code", "scope": "https://www.googleapis.com/auth/drive.file", "prompt": "consent", "login_hint": email, "trigger_onepick": "true", "allow_multiple": "false", "mimetypes": "application/vnd.google-apps.spreadsheet", "state": state, "code_challenge": challenge, "code_challenge_method": "S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
    let requestID = UUID()
    pending = result; pendingID = requestID
    session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: scheme) { [weak self] callback, error in
      guard let self = self else { return }
      guard error == nil, let callback = callback, callback.scheme == scheme, callback.path == "/oauthredirect", let params = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else { self.fail("Spreadsheet selection cancelled or interrupted. Retry while connected.", id: requestID); return }
      var values = [String: String]()
      for item in params { if values[item.name] != nil { self.fail("Invalid Google authorization response.", id: requestID); return }; values[item.name] = item.value ?? "" }
      guard values["state"] == state, values["error"] == nil, let code = values["code"], let id = values["picked_file_ids"], id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { self.fail("Google did not authorize a spreadsheet. Retry selection.", id: requestID); return }
      self.exchange(code: code, client: client, redirect: redirect, verifier: verifier, email: email, id: id, requestID: requestID)
    }
    session?.presentationContextProvider = self
    session?.prefersEphemeralWebBrowserSession = false
    timeout = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in self?.session?.cancel(); self?.fail("Google selection timed out. Retry while connected.", id: requestID) }
    if session?.start() != true { fail("Could not open the Google authorization browser.", id: requestID) }
  }
  private func exchange(code: String, client: String, redirect: String, verifier: String, email: String, id: String, requestID: UUID) {
    var form = URLComponents()
    form.queryItems = ["client_id": client, "code": code, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier].map { URLQueryItem(name: $0.key, value: $0.value) }
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"; request.timeoutInterval = 30
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self else { return }
      guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["access_token"] as? String else { self.fail("Google authorization could not be completed. Check OAuth setup and retry.", id: requestID); return }
      // Reject a different browser account rather than mixing its file with the SDK account.
      var about = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)")!)
      about.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); about.timeoutInterval = 30
      URLSession.shared.dataTask(with: about) { [weak self] data, response, error in
        guard let self = self else { return }
        guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let user = json["user"] as? [String: Any], let actual = user["emailAddress"] as? String, actual.caseInsensitiveCompare(email) == .orderedSame else { self.fail("Choose the same Google account used to connect this installation.", id: requestID); return }
        self.finish(id, id: requestID)
      }.resume()
    }.resume()
  }
}
