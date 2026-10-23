import Foundation
import SwiftUI
import CoreData

// This file is compiled inside the real Feather/BatSign target.
// The Turath/sss files are only the visible shell. Every operation below ends in
// Feather's own Storage, AppFileHandler, DownloadManager and AutoSignManager.

// MARK: - Signing assets backed by Feather Storage

enum SigningAssetError: LocalizedError {
    case wrongP12Extension
    case wrongProvisionExtension
    case emptyFile(String)
    case invalidP12
    case badP12Password
    case invalidProvision
    case expiredProvision
    case certificateMismatch

    var errorDescription: String? {
        switch self {
        case .wrongP12Extension: return "اختر ملف شهادة بامتداد .p12 فقط."
        case .wrongProvisionExtension: return "اختر ملف Provision بامتداد .mobileprovision فقط."
        case .emptyFile(let name): return "الملف \(name) فارغ أو غير قابل للقراءة."
        case .invalidP12: return "ملف P12 غير صالح."
        case .badP12Password: return "كلمة مرور P12 غير صحيحة."
        case .invalidProvision: return "ملف MobileProvision غير صالح."
        case .expiredProvision: return "ملف MobileProvision منتهي الصلاحية."
        case .certificateMismatch: return "شهادة P12 لا تطابق MobileProvision."
        }
    }
}

enum SigningAssetProvider {
    struct Credentials {
        let p12: URL
        let mobileProvision: URL
        let password: String
    }

    @MainActor
    static var selectedCertificate: CertificatePair? {
        let all = Storage.shared.getAllCertificates()
        guard !all.isEmpty else { return nil }
        let selected = UserDefaults.standard.integer(forKey: "feather.selectedCert")
        if all.indices.contains(selected) { return all[selected] }
        if let preferred = all.first(where: { $0.isDefault }) { return preferred }
        return all.first
    }

    @MainActor
    static var hasCredentials: Bool { selectedCertificate != nil }

    @MainActor
    static var hasP12File: Bool {
        guard let cert = selectedCertificate else { return false }
        return Storage.shared.getFile(.certificate, from: cert) != nil
    }

    @MainActor
    static var hasProvisionFile: Bool {
        guard let cert = selectedCertificate else { return false }
        return Storage.shared.getFile(.provision, from: cert) != nil
    }

    @MainActor
    static func credentials() throws -> Credentials {
        guard let cert = selectedCertificate,
              let p12 = Storage.shared.getFile(.certificate, from: cert),
              let provision = Storage.shared.getFile(.provision, from: cert) else {
            throw SigningAssetError.invalidP12
        }
        return Credentials(p12: p12, mobileProvision: provision, password: cert.password ?? "")
    }

    /// Uses the exact Feather/BatSign certificate store. There is no second
    /// Turath certificate folder or keychain, so importing once is enough for
    /// every later sign/clone/injection.
    @MainActor
    static func importCertificate(p12URL: URL, profileURL: URL, password: String) throws {
        let p12Access = p12URL.startAccessingSecurityScopedResource()
        defer { if p12Access { p12URL.stopAccessingSecurityScopedResource() } }
        let provisionAccess = profileURL.startAccessingSecurityScopedResource()
        defer { if provisionAccess { profileURL.stopAccessingSecurityScopedResource() } }
        guard p12URL.pathExtension.lowercased() == "p12" else { throw SigningAssetError.wrongP12Extension }
        guard profileURL.pathExtension.lowercased() == "mobileprovision" else { throw SigningAssetError.wrongProvisionExtension }
        guard FR.checkPasswordForCertificate(for: p12URL, with: password, using: profileURL) else {
            throw SigningAssetError.badP12Password
        }
        guard let decoded = CertificateReader(profileURL).decoded else { throw SigningAssetError.invalidProvision }
        if decoded.ExpirationDate <= Date() { throw SigningAssetError.expiredProvision }

        let fm = FileManager.default
        let uuid = UUID().uuidString
        let folder = fm.certificates(uuid)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let keyTarget = folder.appendingPathComponent("certificate.p12")
        let provisionTarget = folder.appendingPathComponent("certificate.mobileprovision")
        do {
            try Data(contentsOf: p12URL).write(to: keyTarget, options: .atomic)
            try Data(contentsOf: profileURL).write(to: provisionTarget, options: .atomic)
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }

        var insertError: Error?
        Storage.shared.addCertificate(
            uuid: uuid,
            password: password,
            nickname: decoded.Name,
            ppq: decoded.PPQCheck ?? false,
            expiration: decoded.ExpirationDate,
            isDefault: true
        ) { error in insertError = error }
        if let insertError {
            try? fm.removeItem(at: folder)
            throw insertError
        }

        // Certificates are sorted newest first in Feather. Select the one that
        // was just imported and keep using it on every future operation.
        UserDefaults.standard.set(0, forKey: "feather.selectedCert")
    }

    @MainActor
    static func importP12(from source: URL) throws {
        // Kept only for source compatibility with the sss sheet. The actual
        // save is intentionally atomic and happens when both files are present.
        throw SigningAssetError.invalidProvision
    }

    @MainActor
    static func importProvision(from source: URL) throws {
        throw SigningAssetError.invalidP12
    }

    @MainActor
    static func validateAndSavePassword(_ password: String) throws {
        guard selectedCertificate != nil else { throw SigningAssetError.invalidP12 }
    }

    @MainActor
    static func validate(credentials: Credentials) throws {
        guard FR.checkPasswordForCertificate(for: credentials.p12, with: credentials.password, using: credentials.mobileProvision) else {
            throw SigningAssetError.badP12Password
        }
    }

    static func savePassword(_ password: String) throws { }
}

// MARK: - sss setup coordinator, BatSign persistence

@MainActor
final class SigningSetupCoordinator: ObservableObject {
    static let shared = SigningSetupCoordinator()
    @Published var isPresented = false
    private var pendingApp: StoreApp?
    private var pendingAction: (() -> Void)?

    private init() {}

    func request(for app: StoreApp) {
        if SigningAssetProvider.hasCredentials {
            TransferActivityCenter.shared.track(app)
            StoreInstallCoordinator.shared.start(app)
            return
        }
        pendingApp = app
        pendingAction = nil
        isPresented = true
    }

    func request(action: @escaping () -> Void) {
        if SigningAssetProvider.hasCredentials {
            action()
            return
        }
        pendingApp = nil
        pendingAction = action
        isPresented = true
    }

    func completeAfterSetup() {
        guard SigningAssetProvider.hasCredentials else { return }
        let app = pendingApp
        let action = pendingAction
        pendingApp = nil
        pendingAction = nil
        isPresented = false
        if let action { action(); return }
        if let app {
            TransferActivityCenter.shared.track(app)
            StoreInstallCoordinator.shared.start(app)
        }
    }

    func consumePendingApp() -> StoreApp? {
        let app = pendingApp
        pendingApp = nil
        pendingAction = nil
        isPresented = false
        return app
    }

    func cancel() {
        pendingApp = nil
        pendingAction = nil
        isPresented = false
    }
}

// MARK: - Compatibility state used by the sss progress UI

enum StoreInstallPhase: Equatable {
    case idle, downloading, signing, installing, ready, complete, failed
}

struct StoreInstallState: Equatable {
    var phase: StoreInstallPhase = .idle
    var progress: Double = 0
    var message: String? = nil
    var speedText: String? = nil
    var errorMessage: String? { phase == .failed ? message : nil }
}

struct StoreInstallJob: Identifiable, Equatable {
    let id: String
    let appID: String
    let appName: String
    let bundleID: String
    let version: String
    let iconURL: String?
    let downloadURL: String
    let expectedBytes: Int64
}

// MARK: - Real Xxx/BatSign operation bridge

enum XxxBatSignBridge {
    @MainActor
    static func selectedCertificate() -> CertificatePair? {
        SigningAssetProvider.selectedCertificate
    }

    @MainActor
    private static func importedApp(uuid: String) -> Imported? {
        let request: NSFetchRequest<Imported> = Imported.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid)
        request.fetchLimit = 1
        return (try? Storage.shared.context.fetch(request))?.first
    }

    // Enqueueing is not a successful signature. Only the native queue can
    // report whether the operation actually reached the installer.
    @MainActor
    private static func awaitNativeResult(
        uuid: String, app: StoreApp,
        completion: @escaping (Result<StoreApp, Error>) -> Void
    ) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(2 * 60 * 60)
            while Date() < deadline {
                if let result = AutoSignManager.shared.takeShellJobResult(for: uuid) {
                    if result.handedOff {
                        completion(.success(app))
                    } else {
                        completion(.failure(NSError(domain: "XxxBatSignBridge", code: 30,
                            userInfo: [NSLocalizedDescriptionKey: result.errorMessage ?? "تعذر إكمال التوقيع أو تسليم التطبيق للتثبيت."])))
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            completion(.failure(NSError(domain: "XxxBatSignBridge", code: 31,
                userInfo: [NSLocalizedDescriptionKey: "لم تصل نتيجة التوقيع من BatSign. راجع حالة العملية."])))
        }
    }

    /// Import a local IPA with Feather's AppFileHandler, then sign it with
    /// Feather's AutoSignManager. Clone identity and dylibs are only Options;
    /// SigningHandler performs the real bundle rewrite/injection/signing.
    static func importAndQueue(
        ipa: URL,
        metadata: SideloadIPAMetadata?,
        copyNumber: Int?,
        dylibs: [URL],
        progress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<StoreApp, Error>) -> Void
    ) {
        let transferID = "BatSignLibraryOnly_" + UUID().uuidString
        let handler = AppFileHandler(file: ipa, transferID: transferID)

        Task.detached(priority: .userInitiated) {
            do {
                progress(0.08, "جاري استيراد التطبيق")
                try await handler.copy()
                progress(0.18, "جاري فك IPA")
                try await handler.extract()
                progress(0.36, "جاري إضافة التطبيق إلى BatSign")
                try await handler.move()
                try await handler.addToDatabase()
                try? await handler.clean()

                try await MainActor.run {
                    guard let cert = selectedCertificate() else { throw SigningAssetError.invalidP12 }
                    guard let imported = importedApp(uuid: handler.importedAppUUID) else {
                        throw NSError(domain: "XxxBatSignBridge", code: 10, userInfo: [NSLocalizedDescriptionKey: "تعذر العثور على التطبيق بعد استيراده إلى BatSign."])
                    }

                    var options = OptionsManager.shared.options
                    options.signingOption = .default
                    options.post_installAppAfterSigned = true
                    options.post_deleteAppAfterSigned = false
                    options.injectionFiles = dylibs
                    if let number = copyNumber, let base = imported.identifier ?? metadata?.bundleID {
                        options.appIdentifier = base + String(number)
                        options.appName = "\(imported.name ?? metadata?.name ?? "App") \(number)"
                    } else {
                        options.appIdentifier = nil
                        options.appName = nil
                    }

                    progress(0.58, dylibs.isEmpty ? "جاري التوقيع عبر BatSign" : "جاري الحقن والتوقيع عبر BatSign")
                    guard AutoSignManager.shared.enqueue(
                        app: imported,
                        reason: .autoSign,
                        certificate: cert,
                        options: options,
                        force: true
                    ) else {
                        throw NSError(domain: "XxxBatSignBridge", code: 11, userInfo: [NSLocalizedDescriptionKey: "تعذر إضافة عملية التوقيع إلى BatSign."])
                    }

                    let result = StoreApp(
                        id: imported.uuid ?? UUID().uuidString,
                        name: options.appName ?? imported.name ?? metadata?.name ?? "App",
                        bundleId: options.appIdentifier ?? imported.identifier ?? metadata?.bundleID,
                        version: imported.version ?? metadata?.version,
                        fileSize: metadata?.size,
                        notes: nil,
                        iconUrl: nil,
                        featured: nil,
                        categories: nil,
                        installs: nil,
                        updatedAt: nil,
                        addedAt: nil,
                        versionUpdatedAt: nil,
                        feedKind: nil,
                        downloadUrl: nil,
                        downloadURL: nil
                    )
                    progress(0.72, "تم تسليم العملية إلى محرك BatSign")
                    awaitNativeResult(uuid: handler.importedAppUUID, app: result, completion: completion)
                }
            } catch {
                try? await handler.clean()
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Download through Xxx's own DownloadManager. The special library-only id
    /// tells AppFileHandler not to auto-sign with default options. Once Feather
    /// has imported the package, we enqueue the explicit user operation with the
    /// selected persistent certificate and the requested clone/dylib options.
    @MainActor
    static func downloadAndQueue(
        app: StoreApp,
        copyNumber: Int? = nil,
        dylibs: [URL] = [],
        progress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<StoreApp, Error>) -> Void
    ) {
        guard let raw = app.effectiveDownloadURL,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            completion(.failure(NSError(domain: "XxxBatSignBridge", code: 20, userInfo: [NSLocalizedDescriptionKey: "رابط IPA غير صالح."])))
            return
        }
        guard selectedCertificate() != nil else {
            completion(.failure(SigningAssetError.invalidP12))
            return
        }

        let transferID = "BatSignLibraryOnly_" + UUID().uuidString
        let download = DownloadManager.shared.startDownload(
            from: url,
            id: transferID,
            bundleID: app.bundleId,
            displayName: app.name,
            expectedBytes: app.fileSize ?? 0
        )

        Task { @MainActor in
            let deadline = Date().addingTimeInterval(60 * 60 * 2)
            while Date() < deadline {
                if let uuid = download.importedAppUUID, let imported = importedApp(uuid: uuid) {
                    guard let cert = selectedCertificate() else {
                        completion(.failure(SigningAssetError.invalidP12)); return
                    }
                    var options = OptionsManager.shared.options
                    options.signingOption = .default
                    options.post_installAppAfterSigned = true
                    options.post_deleteAppAfterSigned = false
                    options.injectionFiles = dylibs
                    if let number = copyNumber, let base = imported.identifier ?? app.bundleId {
                        options.appIdentifier = base + String(number)
                        options.appName = "\(imported.name ?? app.name) \(number)"
                    } else {
                        options.appIdentifier = nil
                        options.appName = nil
                    }

                    progress(0.72, dylibs.isEmpty ? "جاري التوقيع عبر BatSign" : "جاري الحقن والتوقيع عبر BatSign")
                    guard AutoSignManager.shared.enqueue(
                        app: imported,
                        reason: .autoSign,
                        certificate: cert,
                        options: options,
                        force: true
                    ) else {
                        completion(.failure(NSError(domain: "XxxBatSignBridge", code: 21, userInfo: [NSLocalizedDescriptionKey: "تعذر تشغيل توقيع BatSign."]))); return
                    }
                    let result = StoreApp(
                        id: imported.uuid ?? app.id,
                        name: options.appName ?? imported.name ?? app.name,
                        bundleId: options.appIdentifier ?? imported.identifier ?? app.bundleId,
                        version: imported.version ?? app.version,
                        fileSize: app.fileSize,
                        notes: app.notes,
                        iconUrl: app.iconUrl,
                        featured: app.featured,
                        categories: app.categories,
                        installs: app.installs,
                        updatedAt: app.updatedAt,
                        addedAt: app.addedAt,
                        versionUpdatedAt: app.versionUpdatedAt,
                        feedKind: app.feedKind,
                        downloadUrl: app.downloadUrl,
                        downloadURL: app.downloadURL
                    )
                    awaitNativeResult(uuid: uuid, app: result, completion: completion)
                    return
                }

                if let failure = download.failureMessage {
                    completion(.failure(NSError(domain: "XxxBatSignBridge", code: 23,
                        userInfo: [NSLocalizedDescriptionKey: failure])))
                    return
                }
                let status = download.formattedSpeed.map { "جاري التحميل عبر BatSign · " + $0 }
                    ?? "جاري التحميل عبر BatSign"
                progress(min(0.68, max(0.02, download.transferProgress * 0.68)), status)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            completion(.failure(NSError(domain: "XxxBatSignBridge", code: 22, userInfo: [NSLocalizedDescriptionKey: "انتهت مهلة تجهيز التطبيق في BatSign."])))
        }
    }
}

// MARK: - Store install compatibility, powered only by Xxx

@MainActor
final class StoreInstallCoordinator: ObservableObject {
    static let shared = StoreInstallCoordinator()
    @Published private var states: [String: StoreInstallState] = [:]

    private init() {}
    func bootstrap() {}
    func applicationDidBecomeActive() {
        AutoSignManager.shared.handleForeground()
    }

    func state(for app: StoreApp) -> StoreInstallState {
        states[app.id] ?? .init()
    }

    func start(_ app: StoreApp) {
        if !SigningAssetProvider.hasCredentials {
            SigningSetupCoordinator.shared.request(for: app)
            return
        }
        guard ![.downloading, .signing, .installing].contains(state(for: app).phase) else { return }
        TransferActivityCenter.shared.track(app)
        states[app.id] = StoreInstallState(phase: .downloading, progress: 0.02, message: "جاري التحميل عبر BatSign")

        XxxBatSignBridge.downloadAndQueue(
            app: app,
            progress: { [weak self] value, text in
                Task { @MainActor in
                    let phase: StoreInstallPhase = value >= 0.70 ? .signing : .downloading
                    self?.states[app.id] = StoreInstallState(phase: phase, progress: value, message: text)
                }
            },
            completion: { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        self?.states[app.id] = StoreInstallState(
                            phase: .ready, progress: 1,
                            message: "تم التوقيع وتسليم التطبيق إلى المثبّت"
                        )
                    case .failure(let error):
                        self?.states[app.id] = StoreInstallState(phase: .failed, progress: 0, message: error.localizedDescription)
                    }
                }
            }
        )
    }
}

// MARK: - Duplicate / dylib UI compatibility, real BatSign work

enum DetailPreparationKind: String, Codable { case duplicate, dylib }

@MainActor
final class DetailPreparationCenter: ObservableObject {
    static let shared = DetailPreparationCenter()
    static let completedNotification = Notification.Name("DetailPreparationCenterCompleted")

    @Published private(set) var activeAppID: String?
    @Published private(set) var activeKind: DetailPreparationKind?
    @Published private(set) var busy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText = ""
    @Published private(set) var errorText: String?
    private(set) var activeApp: StoreApp?
    private(set) var activeTargetBundleID: String?
    private(set) var activeVersion: String?

    private init() {}
    func bootstrap() {}
    func handleBackgroundEvents(completionHandler: @escaping () -> Void) { completionHandler() }

    func isActive(appID: String, kind: DetailPreparationKind) -> Bool {
        busy && activeAppID == appID && activeKind == kind
    }

    func beginDuplicate(app: StoreApp, number: Int) {
        guard (1...99).contains(number) else { errorText = "رقم النسخة يجب أن يكون من 1 إلى 99."; return }
        run(app: app, kind: .duplicate, copyNumber: number, dylibs: [])
    }

    func beginDylib(app: StoreApp, dylibs: [URL]) {
        guard !dylibs.isEmpty else { errorText = "اختر ملف Dylib واحدًا على الأقل."; return }
        run(app: app, kind: .dylib, copyNumber: nil, dylibs: dylibs)
    }

    private func run(app: StoreApp, kind: DetailPreparationKind, copyNumber: Int?, dylibs: [URL]) {
        if !SigningAssetProvider.hasCredentials {
            SigningSetupCoordinator.shared.request { [weak self] in
                self?.run(app: app, kind: kind, copyNumber: copyNumber, dylibs: dylibs)
            }
            return
        }
        guard !busy else { return }
        activeApp = app
        activeAppID = app.id
        activeKind = kind
        activeVersion = app.version
        let base = (app.bundleId?.isEmpty == false ? app.bundleId : nil) ?? app.id
        activeTargetBundleID = copyNumber.map { base + String($0) } ?? base
        busy = true
        progress = 0.01
        statusText = "جاري بدء العملية عبر BatSign"
        errorText = nil
        TransferActivityCenter.shared.track(app)

        XxxBatSignBridge.downloadAndQueue(
            app: app,
            copyNumber: copyNumber,
            dylibs: dylibs,
            progress: { [weak self] value, text in
                Task { @MainActor in
                    self?.progress = value
                    self?.statusText = text
                }
            },
            completion: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.busy = false
                    switch result {
                    case .success:
                        self.progress = 1
                        self.statusText = "تم تسليم العملية إلى BatSign"
                        NotificationCenter.default.post(name: Self.completedNotification, object: nil, userInfo: ["appID": app.id, "kind": kind.rawValue])
                    case .failure(let error):
                        self.progress = 0
                        self.statusText = ""
                        self.errorText = error.localizedDescription
                    }
                }
            }
        )
    }
}

// sss calls these only for its own old live-activity/install engine. The real
// target already has BatSign LiveStatus/BSJobKeepAlive, so these compatibility
// hooks deliberately do not start a second activity or keepalive system.
enum InstallLiveActivityBridge {
    static func cleanupStale() {}
}

// Read-only IPA inspection for the SSS file picker; no signing or mutation.
enum XxxSideloadLocator {
    static func locatePayload(in root: URL) -> URL? {
        let direct = root.appendingPathComponent("Payload", isDirectory: true)
        return (try? direct.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? direct : nil
    }

    static func locateApp(in payload: URL) -> URL? {
        let entries = try? FileManager.default.contentsOfDirectory(
            at: payload, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        return entries?.first {
            $0.pathExtension.lowercased() == "app" &&
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
