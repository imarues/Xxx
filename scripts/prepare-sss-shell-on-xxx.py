from pathlib import Path
import shutil
import re

ROOT = Path('.')
SRC = ROOT / 'TurathSource' / 'StoreReplica'
DST = ROOT / 'Feather' / 'TurathShell'
BRIDGE = ROOT / 'Integration' / 'XxxBatSignShellBridge.swift'

if not (SRC / 'Views' / 'RootAndHome.swift').is_file():
    raise SystemExit('rich sss source is missing')
if not BRIDGE.is_file():
    raise SystemExit('XxxBatSignShellBridge.swift is missing')

shutil.rmtree(DST, ignore_errors=True)
(DST / 'Core').mkdir(parents=True, exist_ok=True)
(DST / 'Views').mkdir(parents=True, exist_ok=True)

# UI/content only. The entire StoreReplica/BatSignCore directory is intentionally
# NOT copied into Feather. Feather/Xxx remains the only signing runtime.
for source in (SRC / 'Core').glob('*.swift'):
    shutil.copy2(source, DST / 'Core' / source.name)
for source in (SRC / 'Views').glob('*.swift'):
    shutil.copy2(source, DST / 'Views' / source.name)

# These SSS files are real operational implementations. Remove them and provide
# compatibility types that delegate to Xxx/Feather instead.
for name in [
    'SigningAssets.swift',
    'SigningSetupCoordinator.swift',
    'DetailPreparationCenter.swift',
    'BatSignInstallURLBridge.swift',
    'InstallLiveActivity.swift',
    'TurathAppDelegate.swift',
]:
    (DST / 'Core' / name).unlink(missing_ok=True)

shutil.copy2(BRIDGE, DST / 'Core' / 'XxxBatSignShellBridge.swift')

# The original SSS DownloadsCenter remains the visible UI. Its completed
# downloads previously read only SSS storage, whereas native Feather signs
# into its own queue. Add an SSS-styled record section backed by that queue.
downloads_view = DST / 'Views' / 'DownloadsCenterView.swift'
downloads_text = downloads_view.read_text(encoding='utf-8')
downloads_text = downloads_text.replace(
    '    @ObservedObject private var transfers = TransferActivityCenter.shared',
    '    @ObservedObject private var transfers = TransferActivityCenter.shared\n    @ObservedObject private var featherOperations = XxxOperationLedger.shared',
    1,
)
downloads_text = downloads_text.replace(
    '                    completedSection',
    '                    if !featherOperations.entries.isEmpty { featherOperationsSection }\n                    completedSection',
    1,
)
marker = '    private var completedSection: some View {'
if marker not in downloads_text:
    raise SystemExit('DownloadsCenter section insertion point missing')
new_section = r'''
    // Real Feather/BatSign results, shown inside SSS's existing Downloads tab.
    private var featherOperationsSection: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Text("عمليات التطبيقات")
                .font(AppFont.black(18))
                .foregroundStyle(StoreTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(featherOperations.entries) { operation in
                VStack(alignment: .trailing, spacing: 9) {
                    HStack(spacing: 12) {
                        Image(systemName: operation.kind == .clone ? "square.on.square" :
                                (operation.kind == .injection ? "puzzlepiece.extension.fill" : "arrow.down.app.fill"))
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(StoreTheme.accent)
                            .frame(width: 52, height: 52)
                            .background(StoreTheme.field)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(operation.name)
                                .font(AppFont.black(14))
                                .foregroundStyle(StoreTheme.textPrimary)
                            Text(operation.bundle)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(StoreTheme.textSecondary)
                                .lineLimit(1)
                                .environment(\.layoutDirection, .leftToRight)
                            Text(operation.kind.label + " • " + (operation.size > 0 ? formatBytes(operation.size) : "حجم غير معروف"))
                                .font(AppFont.medium(10))
                                .foregroundStyle(StoreTheme.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        Spacer(minLength: 0)
                    }
                    Text(operation.message)
                        .font(AppFont.regular(11))
                        .foregroundStyle(operation.state == .failed ? Color.red : StoreTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if operation.state == .running {
                        ProgressView(value: operation.progress)
                            .tint(StoreTheme.accent)
                        Text("\(Int(operation.progress * 100))%")
                            .font(AppFont.bold(10))
                            .foregroundStyle(StoreTheme.accent)
                    }
                }
                .padding(13)
                .background(StoreTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(StoreTheme.surfaceBorder, lineWidth: 0.8))
            }
        }
    }

'''
downloads_text = downloads_text.replace(marker, new_section + marker, 1)
downloads_view.write_text(downloads_text, encoding='utf-8')

# IMPORTANT: The header opens SigningHubView and its .apps tab.
# DownloadsCenterView is a separate view and is NOT what that tab displays.
# Bind the actual shown SSS screens (hub + top header) to the native ledger.
def replace_required(data: str, needle: str, replacement: str, file: Path) -> str:
    count = data.count(needle)
    if count != 1:
        raise SystemExit(f"Expected one insertion point in {file}: {needle[:65]} (found {count})")
    return data.replace(needle, replacement, 1)


hub_path = DST / 'Views' / 'SigningHubView.swift'
hub_text = hub_path.read_text(encoding='utf-8')
hub_text = replace_required(
    hub_text,
    '    @ObservedObject private var transfers = TransferActivityCenter.shared',
    '    @ObservedObject private var transfers = TransferActivityCenter.shared\n'
    '    @ObservedObject private var featherOperations = XxxOperationLedger.shared',
    hub_path
)
hub_text = replace_required(
    hub_text,
    '        transfers.activeCount(using: installer, detail: detailCenter)\n    }',
    '        max(transfers.activeCount(using: installer, detail: detailCenter),\n'
    '            featherOperations.entries.count + transfers.activeDirectOperations.count)\n    }',
    hub_path
)
hub_text = replace_required(
    hub_text,
    '            if model.libraryItems.isEmpty && model.directDownloads.isEmpty && activeTransferCount == 0 {',
    '            if !featherOperations.entries.isEmpty { featherOperationsSection }\n'
    '            if model.libraryItems.isEmpty && model.directDownloads.isEmpty && activeTransferCount == 0 {',
    hub_path
)
hub_marker = '    private var downloadsSection: some View {'
hub_text = replace_required(hub_text, hub_marker, new_section + hub_marker, hub_path)
hub_path.write_text(hub_text, encoding='utf-8')

# Header is where the download icon lives, next to settings. Show its red
# number for saved records as well as running downloads.
header_path = DST / 'Views' / 'RootAndHome.swift'
header_text = header_path.read_text(encoding='utf-8')
header_text = replace_required(
    header_text,
    '    @ObservedObject private var transfers = TransferActivityCenter.shared',
    '    @ObservedObject private var transfers = TransferActivityCenter.shared\n'
    '    @ObservedObject private var featherOperations = XxxOperationLedger.shared',
    header_path
)
header_text = replace_required(
    header_text,
    '        transfers.activeCount(using: installer, detail: detailCenter)\n    }',
    '        max(transfers.activeCount(using: installer, detail: detailCenter),\n'
    '            featherOperations.entries.count + transfers.activeDirectOperations.count)\n    }',
    header_path
)
header_path.write_text(header_text, encoding='utf-8')



# SideloadSigningCore is retained only for the UI's metadata, picker vault and
# local-library models. Remove its package mutation/injection implementation.
sideload = DST / 'Core' / 'SideloadSigningCore.swift'
text = sideload.read_text(encoding='utf-8')
text = text.replace('import ZsignSwift\n', '')
text = text.replace('BatSignPackagePipeline.locatePayload(in: root)', 'XxxSideloadLocator.locatePayload(in: root)')
text = text.replace('BatSignPackagePipeline.locateApp(in: payload)', 'XxxSideloadLocator.locateApp(in: payload)')
start_marker = '// MARK: - BatSign-style preparation'
end_marker = '// MARK: - Local library (link + update downloads)'
start = text.find(start_marker)
end = text.find(end_marker)
if start < 0 or end < 0 or end <= start:
    raise SystemExit('Could not strip SSS package preparer')
text = text[:start] + end_marker + text[end + len(end_marker):]
sideload.write_text(text, encoding='utf-8')


def replace_function_body(path: Path, marker: str, new_function: str):
    data = path.read_text(encoding='utf-8')
    start = data.find(marker)
    if start < 0:
        raise SystemExit(f'Could not locate {marker} in {path}')
    brace = data.find('{', start)
    depth = 0
    end = None
    for i in range(brace, len(data)):
        c = data[i]
        if c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f'Unbalanced function in {path}: {marker}')
    path.write_text(data[:start] + new_function + data[end:], encoding='utf-8')

# The rich signing hub keeps its exact UI. Only the action behind its button is
# swapped: local/link IPA -> Feather AppFileHandler -> AutoSignManager.
hub = DST / 'Views' / 'SigningHubView.swift'
replace_function_body(
    hub,
    '    private func prepareAndInstall(',
    '''    private func prepareAndInstall(
        sourceIPA: URL,
        knownMetadata: SideloadIPAMetadata?,
        sourceKind: SideloadSourceKind,
        sourceURL: String?,
        alreadyBusy: Bool = false
    ) {
        if !alreadyBusy {
            guard !busy else { return }
            busy = true
        }
        errorText = nil
        workProgress = 0
        statusText = "جاري تجهيز التطبيق عبر BatSign"
        preparedApp = nil

        let variant = copyVariant
        let selectedDylibs = dylibs

        let execute = {
            XxxBatSignBridge.importAndQueue(
                ipa: sourceIPA,
                metadata: knownMetadata,
                copyNumber: variant.number,
                dylibs: selectedDylibs,
                operationKind: sourceKind == .link ? .download : .localFile,
                progress: { fraction, text in
                    DispatchQueue.main.async {
                        self.workProgress = fraction
                        self.statusText = text
                    }
                },
                completion: { result in
                    DispatchQueue.main.async {
                        self.busy = false
                        switch result {
                        case .success(let app):
                            self.workProgress = 1
                            self.preparedApp = app
                            self.statusText = "تم تسليم التطبيق إلى BatSign للتوقيع والتثبيت"
                            TransferActivityCenter.shared.track(app)
                            self.refreshLibrary()
                        case .failure(let error):
                            self.errorText = error.localizedDescription
                            self.statusText = ""
                        }
                    }
                }
            )
        }

        DispatchQueue.main.async {
            if SigningAssetProvider.hasCredentials {
                execute()
            } else {
                self.busy = false
                SigningSetupCoordinator.shared.request(action: execute)
            }
        }
    }'''
)

# Keep SSS view names scoped away from the preserved native Feather screens.
for path in DST.rglob('*.swift'):
    data = path.read_text(encoding='utf-8')
    data = re.sub(r'\bUpdatesView\b', 'SSSUpdatesView', data)
    path.write_text(data, encoding='utf-8')

# Only UI queries need main-actor isolation. URLSession delegates remain on
# their own queue and keep the source's explicit main-queue publication.
transfer = DST / 'Core' / 'TransferActivityCenter.swift'
data = transfer.read_text(encoding='utf-8')
for marker in ['    func activeInstallOperations(', '    func activeCount(']:
    data = data.replace(marker, '    @MainActor\n' + marker)
transfer.write_text(data, encoding='utf-8')

# Feather's certificate store is main-context based. Finish persistence before
# dismissing the setup sheet or executing its pending signing action.
replace_function_body(
    DST / 'Views' / 'Components.swift',
    '    private func importNow()',
    '''    private func importNow() {
        guard let p12URL, let profileURL else { return }
        working = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try SigningAssetProvider.importCertificate(
                    p12URL: p12URL, profileURL: profileURL, password: password
                )
                working = false
                onReady()
                dismiss()
            } catch {
                working = false
                errorMessage = error.localizedDescription
            }
        }
    }'''
)

# The older detail sheet is kept in source as well, but its package operation
# must use the native bridge instead of the excluded SSS preparer.
replace_function_body(
    DST / 'Views' / 'DetailAppActions.swift',
    '    private func prepare(',
    '''    private func prepare(localURL: URL, app: StoreApp, sourceURL: String, mode: DetailPackageActionMode, completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            let number = mode == .duplicate ? self.copyVariant.number : nil
            let files = mode == .dylib ? self.dylibs : []
            SigningSetupCoordinator.shared.request {
                XxxBatSignBridge.importAndQueue(
                    ipa: localURL, metadata: nil, copyNumber: number, dylibs: files,
                    progress: { value, text in
                        DispatchQueue.main.async {
                            self.progress = 0.42 + value * 0.58
                            self.status = text
                        }
                    },
                    completion: { result in
                        DispatchQueue.main.async {
                            self.busy = false
                            switch result {
                            case .success:
                                self.progress = 1
                                self.status = "تم تسليم العملية إلى BatSign"
                                completion()
                            case .failure(let error):
                                self.status = ""
                                self.errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
            }
        }
    }'''
)

# Replace the Feather visual root with SSS while preserving FeatherApp itself,
# its AppDelegate, CoreData context, lifecycle, keepalive and managers.
app = ROOT / 'Feather' / 'FeatherApp.swift'
data = app.read_text(encoding='utf-8')

if '@StateObject private var turathStore = StoreViewModel()' not in data:
    needle = '@StateObject private var autoUpdateManager = AutoUpdateManager.shared\n'
    if needle not in data:
        raise SystemExit('FeatherApp state insertion point not found')
    data = data.replace(
        needle,
        needle + '\t@StateObject private var turathStore = StoreViewModel()\n\t@ObservedObject private var signingSetup = SigningSetupCoordinator.shared\n',
        1,
    )

start = data.find('\t\t\tVStack {')
if start < 0:
    raise SystemExit('FeatherApp visible root VStack not found')
# Match just the root VStack block.
brace = data.find('{', start)
depth = 0
end = None
for i in range(brace, len(data)):
    c = data[i]
    if c == '{': depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end is None:
    raise SystemExit('FeatherApp root VStack is unbalanced')

new_root = '''\t\t\tRootStoreView()
\t\t\t\t.environmentObject(turathStore)
\t\t\t\t.environment(\\.managedObjectContext, storage.context)
\t\t\t\t.environment(\\.layoutDirection, .rightToLeft)
\t\t\t\t.preferredColorScheme(.dark)
\t\t\t\t.onOpenURL(perform: _handleURL)
\t\t\t\t.fullScreenCover(
\t\t\t\t\tisPresented: $signingSetup.isPresented,
\t\t\t\t\tonDismiss: { signingSetup.cancel() }
\t\t\t\t) {
\t\t\t\t\tSigningSetupSheet {
\t\t\t\t\t\tsigningSetup.completeAfterSetup()
\t\t\t\t\t}
\t\t\t\t}
'''
data = data[:start] + new_root + data[end:]

onappear = '\t\t\t.onAppear {\n'
if 'XxxSSSShellBootstrapped' not in data:
    insert = '''\t\t\t.onAppear {
\t\t\t\tUserDefaults.standard.set(true, forKey: "XxxSSSShellBootstrapped")
\t\t\t\tFontLoader.registerBundledPingAR()
\t\t\t\tAppVisibleFolders.bootstrap()
\t\t\t\tDetailPreparationCenter.shared.bootstrap()
\t\t\t\tTransferActivityCenter.shared.bootstrap()
\t\t\t\tTask { await KiraPagesUpdatesService.shared.warm() }
'''
    if onappear not in data:
        raise SystemExit('FeatherApp onAppear not found')
    data = data.replace(onappear, insert, 1)

app.write_text(data, encoding='utf-8')

# Hard architecture checks. The mounted visible shell must not carry the SSS
# signing engine, certificate store or low-level injector.
for forbidden in [
    'BatSignSigner',
    'BatSignPackagePipeline',
    'Zsign.injectDyLib',
    'Zsign.sign(',
    'SecPKCS12Import',
    'keychainService = "com.ikiraplus.turathreplica.signing"',
]:
    hits = []
    for p in DST.rglob('*.swift'):
        if p.name == 'XxxBatSignShellBridge.swift':
            continue
        if forbidden in p.read_text(encoding='utf-8', errors='ignore'):
            hits.append(str(p))
    if hits:
        raise SystemExit(f'Forbidden SSS operational backend {forbidden}: {hits}')

# Visible actions must now route through the Xxx bridge.
checks = {
    DST / 'Views' / 'SigningHubView.swift': 'XxxBatSignBridge.importAndQueue',
    DST / 'Core' / 'XxxBatSignShellBridge.swift': 'AutoSignManager.shared.enqueue',
    ROOT / 'Feather' / 'FeatherApp.swift': 'RootStoreView()',
}
for path, needle in checks.items():
    if needle not in path.read_text(encoding='utf-8'):
        raise SystemExit(f'Missing integration marker {needle} in {path}')

print('sss UI mounted on the real Feather target; SSS operational signing backend excluded.')
''