import Foundation
import Observation
import Security

/// Nächster Termin für ein Schreibtischgerät mit eigenem „Briefkasten“-Worker (Kalli 0.17.0).
///
/// Das Gerät erreicht den Mac im WLAN nicht. Kalli legt deshalb den nächsten Termin per HTTPS in einem
/// Briefkasten ab, den das Gerät abholt. **Standardmäßig aus.** Erst mit eingeschaltetem Schalter, Adresse und
/// Schreibschlüssel verlässt etwas Kalli. Gesendet werden nur Titel (gekürzt) und Beginn des Termins, den Kallis
/// Menüleiste ohnehin als nächsten kennt – nie Teilnehmer, Ort, Notizen oder Kalendername. Nie Titel ins Protokoll.
enum KumikiTermin {
    static let enabledKey = "kumikiTerminSenden"
    static let urlKey = "kumikiTerminURL"
    static let header = "x-briefkasten-key"
    /// Mehr zeigt das Gerät nicht an (Briefkasten nimmt höchstens 60).
    static let maxTitle = 40
    /// Lebenszeichen, damit das Gerät einen alten Stand erkennt.
    static let heartbeat: TimeInterval = 300

    // MARK: Reine Teile (getestet)

    /// Nur `https://` mit Host, ohne Zugangsdaten, Abfrage oder Fragment.
    static func validURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 256, let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    /// Druckbares ASCII ohne Leerzeichen, 20–256 Zeichen.
    static func validKey(_ key: String) -> Bool {
        (20...256).contains(key.count) && key.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }

    /// Titel ohne Steuerzeichen, auf `maxTitle` Zeichen gekürzt.
    static func cleanTitle(_ title: String) -> String {
        let flat = String(String.UnicodeScalarView(title.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : $0
        }))
        return String(flat.trimmingCharacters(in: .whitespaces).prefix(maxTitle))
    }

    /// `{"v":1,"termin":{"titel":…,"beginn":…}}` bzw. `{"v":1,"termin":null}`.
    static func payload(_ item: AgendaItem?) -> [String: Any] {
        guard let item, case .event = item.kind, !item.isAllDay, let start = item.start else {
            return ["v": 1, "termin": NSNull()]
        }
        return ["v": 1, "termin": ["titel": cleanTitle(item.title), "beginn": Int(start.timeIntervalSince1970.rounded())]]
    }

    static func message(status: Int?, error: Error?) -> String {
        if let status {
            switch status {
            case 200...299: return "Gesendet um \(time.string(from: Date()))"
            case 401, 403: return "Briefkasten lehnt den Schlüssel ab"
            case 429: return "Briefkasten bremst, nächster Versuch später"
            default: return "Briefkasten antwortet mit Fehler \(status)"
            }
        }
        if let error = error as? URLError, error.code == .notConnectedToInternet { return "Keine Internetverbindung" }
        return "Briefkasten nicht erreichbar"
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: Einstellungen

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var url: URL? { UserDefaults.standard.string(forKey: urlKey).flatMap(validURL) }

    static func save(url text: String, key: String) throws {
        guard let url = validURL(text) else { throw KumikiTerminError.invalidURL }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validKey(key) else { throw KumikiTerminError.invalidKey }
        try KumikiTerminKeychain.save(key)
        UserDefaults.standard.set(url.absoluteString, forKey: urlKey)
    }
}

enum KumikiTerminError: LocalizedError {
    case invalidURL, invalidKey, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Die Adresse muss mit https:// beginnen."
        case .invalidKey: return "Der Schlüssel hat nicht das erwartete Format."
        case .keychain(let s): return "Der Schlüssel konnte nicht im Schlüsselbund gespeichert werden (Fehler \(s))."
        }
    }
}

/// Eigener Schlüsselbund-Eintrag, nicht synchronisiert.
enum KumikiTerminKeychain {
    nonisolated(unsafe) private static let query: [String: Any] = [   // nur gelesen, nie verändert
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.kalli.app.kumiki",
        kSecAttrAccount as String: "briefkasten-termin",
    ]

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count <= 256,
              let key = String(data: data, encoding: .utf8), KumikiTermin.validKey(key) else { return nil }
        return key
    }

    static func exists() -> Bool { read() != nil }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KumikiTerminError.keychain(status) }
    }
}

/// Folgt keiner Weiterleitung: URLSession schickte den Schlüssel-Header sonst ans neue Ziel mit.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Sendet bei jeder Änderung des nächsten Termins und alle 5 min als Lebenszeichen.
@MainActor
@Observable
final class KumikiTerminSender {

    /// Letztes Ergebnis für die Einstellungen. Eigene Apps scheitern nie stumm.
    private(set) var status: String?

    @ObservationIgnored private let current: @MainActor () -> AgendaItem?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var pending = false
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    init(current: @escaping @MainActor () -> AgendaItem?) { self.current = current }

    func start() {
        observe()
        timer = Timer.scheduledTimer(withTimeInterval: KumikiTermin.heartbeat, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send() }
        }
        timer?.tolerance = 30
        send()
    }

    private func observe() {
        withObservationTracking { _ = current() } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.send()
                    self?.observe()
                }
            }
        }
    }

    /// Sofort senden (Schalter an, Schlüssel gespeichert). Läuft schon eine Anfrage, folgt eine danach.
    func send() {
        guard KumikiTermin.isEnabled else { return }
        guard !sending else { pending = true; return }
        guard let url = KumikiTermin.url, let key = KumikiTerminKeychain.read() else {
            status = "Adresse und Schlüssel fehlen"
            return
        }
        guard let body = try? JSONSerialization.data(withJSONObject: KumikiTermin.payload(current()), options: [.sortedKeys])
        else { status = "Termin ließ sich nicht verpacken"; return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: KumikiTermin.header)
        sending = true
        Task {
            var code: Int?
            var failure: Error?
            do {
                let (_, response) = try await session.data(for: request)
                code = (response as? HTTPURLResponse)?.statusCode
            } catch { failure = error }
            sending = false
            status = KumikiTermin.message(status: code, error: failure)
            if pending { pending = false; send() }
        }
    }
}
