#!/bin/bash
set -euo pipefail

ROOT="TurathSource/StoreReplica"

# Rich sss surfaces that must exist.
for f in \
  "$ROOT/Views/SigningHubView.swift" \
  "$ROOT/Views/DownloadsCenterView.swift" \
  "$ROOT/Views/SearchFastView.swift" \
  "$ROOT/Views/AppCloneSheet.swift" \
  "$ROOT/Views/AppDylibMergeSheet.swift" \
  "$ROOT/Views/ActiveTransfersInlineView.swift" \
  "$ROOT/Core/DetailPreparationCenter.swift" \
  "$ROOT/Core/DirectDownloadLibrary.swift" \
  "$ROOT/Core/TransferActivityCenter.swift" \
  "$ROOT/Core/SideloadSigningCore.swift"; do
  test -f "$f"
done

# All final signing must route through BatSignSigner.
mapfile -t SIGN_CALLS < <(grep -R -l 'Zsign\.sign(' "$ROOT" --include='*.swift' || true)
if [ "${#SIGN_CALLS[@]}" -ne 1 ] || [[ "${SIGN_CALLS[0]}" != *"/BatSignCore/BatSignSigner.swift" ]]; then
  printf 'Unexpected direct Zsign.sign routes:\n%s\n' "${SIGN_CALLS[*]:-none}"
  exit 1
fi

# All Mach-O dylib injection must also route through BatSignSigner.
mapfile -t INJECT_CALLS < <(grep -R -l 'Zsign\.injectDyLib(' "$ROOT" --include='*.swift' || true)
if [ "${#INJECT_CALLS[@]}" -ne 1 ] || [[ "${INJECT_CALLS[0]}" != *"/BatSignCore/BatSignSigner.swift" ]]; then
  printf 'Unexpected direct Zsign.injectDyLib routes:\n%s\n' "${INJECT_CALLS[*]:-none}"
  exit 1
fi

grep -F 'BatSignSigner.inject(dylibs: urls, into: appURL)' "$ROOT/Core/SideloadSigningCore.swift"
grep -F 'StoreInstallCoordinator.shared.start' "$ROOT/Views/SigningHubView.swift"
grep -F 'StoreInstallCoordinator.shared.start' "$ROOT/Core/DetailPreparationCenter.swift"
grep -F 'SigningSetupCoordinator.shared.request' "$ROOT/Views/SigningHubView.swift"
grep -F 'SigningSetupCoordinator.shared.request' "$ROOT/Core/DetailPreparationCenter.swift"
grep -F 'SigningHubView()' "$ROOT/Views/RootAndHome.swift"
grep -F 'SearchFastView()' "$ROOT/Views/RootAndHome.swift"

echo "Rich sss features present and signing/dylib routes are centralized in BatSignCore."
