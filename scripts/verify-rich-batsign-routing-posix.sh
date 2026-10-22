#!/bin/bash
set -euo pipefail

ROOT="TurathSource/StoreReplica"

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

SIGN_CALLS=$(grep -R -l 'Zsign\.sign(' "$ROOT" --include='*.swift' || true)
SIGN_COUNT=$(printf '%s\n' "$SIGN_CALLS" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$SIGN_COUNT" -ne 1 ] || ! printf '%s\n' "$SIGN_CALLS" | grep -q '/BatSignCore/BatSignSigner.swift$'; then
  printf 'Unexpected direct Zsign.sign routes:\n%s\n' "${SIGN_CALLS:-none}"
  exit 1
fi

INJECT_CALLS=$(grep -R -l 'Zsign\.injectDyLib(' "$ROOT" --include='*.swift' || true)
INJECT_COUNT=$(printf '%s\n' "$INJECT_CALLS" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$INJECT_COUNT" -ne 1 ] || ! printf '%s\n' "$INJECT_CALLS" | grep -q '/BatSignCore/BatSignSigner.swift$'; then
  printf 'Unexpected direct Zsign.injectDyLib routes:\n%s\n' "${INJECT_CALLS:-none}"
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
