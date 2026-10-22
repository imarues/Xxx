import Foundation

/// Internal BatSign capability bridge for the Turath/sss shell.
///
/// This type deliberately has no SwiftUI surface. The visible application stays
/// identical to sss, while signing/install capabilities remain callable from
/// the existing Turath controls and from future internal integrations.
final class HiddenBatSignRuntime {
    static let shared = HiddenBatSignRuntime()

    private init() {}

    /// Warm the backend without presenting any BatSign/Feather UI.
    func bootstrap() {
        _ = SigningAssetProvider.hasCredentials
        StoreInstallCoordinator.shared.bootstrap()
    }

    var hasSigningCredentials: Bool {
        SigningAssetProvider.hasCredentials
    }

    func importCertificate(
        p12URL: URL,
        profileURL: URL,
        password: String
    ) throws {
        try SigningAssetProvider.importCertificate(
            p12URL: p12URL,
            profileURL: profileURL,
            password: password
        )
    }

    func validateSigningCredentials() throws {
        let credentials = try SigningAssetProvider.credentials()
        try SigningAssetProvider.validate(credentials: credentials)
    }

    func validateIPA(at url: URL) -> Bool {
        BatSignPackagePipeline.validateImportableIPA(at: url)
    }

    /// Low-level app-bundle signing entry point retained for internal tools.
    func signApp(at appURL: URL) throws {
        let credentials = try SigningAssetProvider.credentials()
        try BatSignSigner.sign(appURL: appURL, credentials: credentials)
    }

    /// Complete BatSign package pipeline: unpack -> sign -> repackage/cache.
    func signPackage(
        ipaURL: URL,
        job: StoreInstallJob,
        outputURL: URL,
        progress: ((BatSignPackageStage, Double) -> Void)? = nil
    ) throws -> BatSignPackageArtifact {
        let credentials = try SigningAssetProvider.credentials()
        return try BatSignPackagePipeline.sign(
            ipaURL: ipaURL,
            job: job,
            credentials: credentials,
            outputURL: outputURL,
            progress: progress
        )
    }

    /// Uses the same coordinator that the sss Install buttons already use.
    func install(_ app: StoreApp) {
        StoreInstallCoordinator.shared.start(app)
    }

    /// Requests the existing sss certificate sheet; this does not add any new UI.
    func requestSigningSetup(for app: StoreApp) {
        SigningSetupCoordinator.shared.request(for: app)
    }
}
