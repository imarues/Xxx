from pathlib import Path

path = Path("Feather/TurathShell/Views/AppCloneSheet.swift")
if not path.is_file():
    raise SystemExit("Generated AppCloneSheet.swift is missing; run prepare-sss-shell-on-xxx.py first")

text = path.read_text(encoding="utf-8")

observer_needle = '    @Environment(\\.dismiss) private var dismiss\n'
observer_replacement = observer_needle + '    @ObservedObject private var preparation = DetailPreparationCenter.shared\n'
if observer_needle not in text:
    raise SystemExit("AppCloneSheet observer insertion point not found")
text = text.replace(observer_needle, observer_replacement, 1)

layout_needle = '''                numberCard\n\n                Button(action: startDuplicate) {'''
layout_replacement = '''                numberCard\n\n                if preparation.activeAppID == app.id && preparation.activeKind == .duplicate &&\n                    (preparation.busy || preparation.progress > 0 || !preparation.statusText.isEmpty || preparation.errorText != nil) {\n                    duplicateProgressCard\n                }\n\n                Button(action: startDuplicate) {'''
if layout_needle not in text:
    raise SystemExit("AppCloneSheet progress insertion point not found")
text = text.replace(layout_needle, layout_replacement, 1)

text = text.replace(
    '                .disabled(!customIsValid)\n                .opacity(customIsValid ? 1 : 0.62)',
    '''                .disabled(!customIsValid || (preparation.busy && preparation.activeAppID == app.id))\n                .opacity((customIsValid && !(preparation.busy && preparation.activeAppID == app.id)) ? 1 : 0.62)''',
    1,
)

start_marker = '    private func startDuplicate() {'
start = text.find(start_marker)
if start < 0:
    raise SystemExit("AppCloneSheet startDuplicate not found")
brace = text.find('{', start)
depth = 0
end = None
for i in range(brace, len(text)):
    if text[i] == '{':
        depth += 1
    elif text[i] == '}':
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end is None:
    raise SystemExit("AppCloneSheet startDuplicate is unbalanced")

new_start = '''    private func startDuplicate() {\n        guard customIsValid else { return }\n        // Keep this sheet visible. DetailPreparationCenter is the native Xxx/BatSign\n        // bridge and publishes the real download/sign/install hand-off progress.\n        preparation.beginDuplicate(app: app, number: effectiveNumber)\n    }'''
text = text[:start] + new_start + text[end:]

progress_view = '''\n    private var duplicateProgressCard: some View {\n        let value = max(0, min(preparation.progress, 1))\n        return VStack(alignment: .trailing, spacing: 12) {\n            HStack(spacing: 10) {\n                Text(value >= 1 && !preparation.busy ? "اكتملت العملية" : "جاري تجهيز النسخة")\n                    .font(AppFont.black(16))\n                    .foregroundStyle(StoreTheme.textPrimary)\n                Spacer()\n                Text("\\(Int(value * 100))%")\n                    .font(.system(size: 13, weight: .bold, design: .rounded))\n                    .foregroundStyle(StoreTheme.accent)\n                    .environment(\\.layoutDirection, .leftToRight)\n            }\n\n            ProgressView(value: value)\n                .tint(StoreTheme.accent)\n                .frame(maxWidth: .infinity)\n\n            if let error = preparation.errorText, !error.isEmpty {\n                Text(error)\n                    .font(AppFont.regular(12.5))\n                    .foregroundStyle(Color.red.opacity(0.95))\n                    .multilineTextAlignment(.trailing)\n                    .frame(maxWidth: .infinity, alignment: .trailing)\n            } else if !preparation.statusText.isEmpty {\n                Text(preparation.statusText)\n                    .font(AppFont.regular(12.5))\n                    .foregroundStyle(StoreTheme.textSecondary)\n                    .multilineTextAlignment(.trailing)\n                    .frame(maxWidth: .infinity, alignment: .trailing)\n            }\n        }\n        .padding(16)\n        .background(StoreTheme.surface.opacity(0.93))\n        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))\n        .overlay {\n            RoundedRectangle(cornerRadius: 22, style: .continuous)\n                .stroke(StoreTheme.surfaceBorder.opacity(0.85), lineWidth: 0.8)\n        }\n    }\n\n'''
header_marker = '    private var header: some View {'
if header_marker not in text:
    raise SystemExit("AppCloneSheet header insertion point not found")
text = text.replace(header_marker, progress_view + header_marker, 1)

# Architecture guard: cloning must remain on the native Xxx bridge and the sheet
# must not dismiss itself when the job starts.
if 'preparation.beginDuplicate(app: app, number: effectiveNumber)' not in text:
    raise SystemExit("Clone bridge marker missing")
start_block = text[text.find(start_marker):text.find(progress_view.strip())]
if 'dismiss()' in start_block:
    raise SystemExit("Clone flow still dismisses the sheet")

path.write_text(text, encoding="utf-8")
print("Clone sheet now stays open and shows native Xxx/BatSign progress.")
