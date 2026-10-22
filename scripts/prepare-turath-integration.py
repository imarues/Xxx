from pathlib import Path

app = Path("TurathSource/StoreReplica/App.swift")
text = app.read_text(encoding="utf-8")

needle = """                .task {\n                    InstallLiveActivityBridge.cleanupStale()\n                    StoreInstallCoordinator.shared.bootstrap()\n"""
replacement = """                .task {\n                    HiddenBatSignRuntime.shared.bootstrap()\n                    InstallLiveActivityBridge.cleanupStale()\n                    StoreInstallCoordinator.shared.bootstrap()\n"""

if "HiddenBatSignRuntime.shared.bootstrap()" not in text:
    if needle not in text:
        raise SystemExit("Could not locate Turath App.swift task bootstrap block")
    text = text.replace(needle, replacement, 1)
    app.write_text(text, encoding="utf-8")

bridge = Path("TurathSource/StoreReplica/Bridge/HiddenBatSignRuntime.swift")
if not bridge.is_file():
    raise SystemExit("Hidden BatSign runtime bridge was not copied into Turath target")

root = Path("TurathSource/StoreReplica/Views/RootAndHome.swift").read_text(encoding="utf-8")
required_tabs = 'case home = "الرئيسية", explore = "استكشف", updates = "التحديثات", shop = "المتجر", search = "البحث"'
if required_tabs not in root:
    raise SystemExit("sss visible tab contract changed unexpectedly")

for view in Path("TurathSource/StoreReplica/Views").glob("*.swift"):
    body = view.read_text(encoding="utf-8", errors="ignore")
    for forbidden in ("VariedTabbarView", "FeatherApp", "WSSettings", "CertificateView"):
        if forbidden in body:
            raise SystemExit(f"Hidden BatSign/Feather UI leaked into visible sss views: {forbidden} in {view}")

print("Hidden BatSign backend bridge injected; visible UI remains the pinned sss shell.")
