from pathlib import Path

ROOT = Path("TurathSource/StoreReplica")


def replace_function_body(path: Path, marker: str, new_function: str) -> None:
    text = path.read_text(encoding="utf-8")
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"Could not locate {marker} in {path}")
    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit(f"Could not locate opening brace for {marker} in {path}")
    depth = 0
    end = None
    for i in range(brace, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"Could not match braces for {marker} in {path}")
    text = text[:start] + new_function + text[end:]
    path.write_text(text, encoding="utf-8")


# 1) Keep the rich sss UI intact, only warm the hidden BatSign backend.
app = ROOT / "App.swift"
text = app.read_text(encoding="utf-8")
needle = """                .task {\n                    InstallLiveActivityBridge.cleanupStale()\n                    StoreInstallCoordinator.shared.bootstrap()\n"""
replacement = """                .task {\n                    HiddenBatSignRuntime.shared.bootstrap()\n                    InstallLiveActivityBridge.cleanupStale()\n                    StoreInstallCoordinator.shared.bootstrap()\n"""
if "HiddenBatSignRuntime.shared.bootstrap()" not in text:
    if needle not in text:
        raise SystemExit("Could not locate rich Turath App.swift task bootstrap block")
    app.write_text(text.replace(needle, replacement, 1), encoding="utf-8")

# 2) Route the rich sideload dylib flow through BatSignSigner instead of calling
#    Zsign directly from SideloadSigningCore.
sideload = ROOT / "Core" / "SideloadSigningCore.swift"
replace_function_body(
    sideload,
    "    private static func injectDylibs(_ urls: [URL], into appURL: URL) throws",
    """    private static func injectDylibs(_ urls: [URL], into appURL: URL) throws {\n        try BatSignSigner.inject(dylibs: urls, into: appURL)\n    }"""
)

# Remove the now-unneeded direct Zsign import from the sideload preparation layer.
sideload_text = sideload.read_text(encoding="utf-8")
sideload_text = sideload_text.replace("import ZsignSwift\n", "")
sideload.write_text(sideload_text, encoding="utf-8")

# 3) Preserve the richer dylib compatibility fix, but centralize it inside the
#    BatSign signer itself before the Mach-O injection.
signer = ROOT / "BatSignCore" / "BatSignSigner.swift"
signer_text = signer.read_text(encoding="utf-8")
copy_line = "            try FileManager.default.copyItem(at: source, to: target)\n"
compat = """            try FileManager.default.copyItem(at: source, to: target)\n\n            _ = Zsign.changeDylibPath(\n                appExecutable: target.path,\n                for: \"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate\",\n                with: \"@rpath/CydiaSubstrate.framework/CydiaSubstrate\"\n            )\n"""
if "Zsign.changeDylibPath(" not in signer_text:
    if copy_line not in signer_text:
        raise SystemExit("Could not locate BatSign dylib copy step")
    signer_text = signer_text.replace(copy_line, compat, 1)
    signer.write_text(signer_text, encoding="utf-8")

# 4) Verify the rich sss surface really is the enhanced version the user asked for.
required_files = [
    ROOT / "Views" / "SigningHubView.swift",
    ROOT / "Views" / "DownloadsCenterView.swift",
    ROOT / "Views" / "SearchFastView.swift",
    ROOT / "Views" / "AppCloneSheet.swift",
    ROOT / "Views" / "AppDylibMergeSheet.swift",
    ROOT / "Views" / "ActiveTransfersInlineView.swift",
    ROOT / "Core" / "DetailPreparationCenter.swift",
    ROOT / "Core" / "DirectDownloadLibrary.swift",
    ROOT / "Core" / "TransferActivityCenter.swift",
    ROOT / "Core" / "SideloadSigningCore.swift",
]
for path in required_files:
    if not path.is_file():
        raise SystemExit(f"Rich sss feature missing: {path}")

root = (ROOT / "Views" / "RootAndHome.swift").read_text(encoding="utf-8")
required_tabs = 'case home = "الرئيسية", explore = "استكشف", updates = "التحديثات", shop = "المتجر", search = "البحث"'
if required_tabs not in root or "SigningHubView()" not in root or "SearchFastView()" not in root:
    raise SystemExit("Rich sss visible shell is not the expected enhanced version")

# 5) Verify every visible signing/clone/dylib action ends at the BatSign-backed
#    coordinator, while Feather/BatSign's own UI remains invisible.
signing_hub = (ROOT / "Views" / "SigningHubView.swift").read_text(encoding="utf-8")
detail_center = (ROOT / "Core" / "DetailPreparationCenter.swift").read_text(encoding="utf-8")
for body, name in ((signing_hub, "SigningHubView"), (detail_center, "DetailPreparationCenter")):
    if "StoreInstallCoordinator.shared.start" not in body:
        raise SystemExit(f"{name} is not routed to the BatSign-backed install coordinator")
    if "SigningSetupCoordinator.shared.request" not in body:
        raise SystemExit(f"{name} is not routed to the shared signing credentials flow")

for view in (ROOT / "Views").glob("*.swift"):
    body = view.read_text(encoding="utf-8", errors="ignore")
    for forbidden in ("VariedTabbarView", "FeatherApp", "WSSettings", "CertificateView"):
        if forbidden in body:
            raise SystemExit(f"BatSign/Feather UI leaked into visible sss views: {forbidden} in {view}")

# 6) Hard audit: low-level signing and Mach-O injection may only live in
#    BatSignCore/BatSignSigner.swift.
for path in ROOT.rglob("*.swift"):
    body = path.read_text(encoding="utf-8", errors="ignore")
    rel = path.relative_to(ROOT).as_posix()
    if "Zsign.sign(" in body and rel != "BatSignCore/BatSignSigner.swift":
        raise SystemExit(f"Direct Zsign.sign outside BatSignSigner: {rel}")
    if "Zsign.injectDyLib(" in body and rel != "BatSignCore/BatSignSigner.swift":
        raise SystemExit(f"Direct Zsign.injectDyLib outside BatSignSigner: {rel}")

print("Rich sss signing hub verified; all low-level signing/injection routes are centralized in BatSignSigner.")
