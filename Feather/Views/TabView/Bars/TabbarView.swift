import SwiftUI

struct TabbarView: View {
    @State private var selectedTab: TabEnum = TabEnum(rawValue: UserDefaults.standard.string(forKey: "BatSign.defaultTab") ?? "") ?? .today
    @Namespace private var tabAnimation

    private let tabs: [TabEnum] = [.today, .sources, .apps, .updates, .library, .search]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(bsHex: 0x0B1020).ignoresSafeArea()

            TabEnum.view(for: selectedTab)
                .padding(.bottom, 82)
                .id(selectedTab)

            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        BSHaptics.tap()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            selectedTab = tab
                            UserDefaults.standard.set(tab.rawValue, forKey: "BatSign.defaultTab")
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selectedTab == tab ? Color(bsHex: 0x7AA2FF) : Color(bsHex: 0x7B84A1))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(Color(bsHex: 0x7AA2FF, alpha: 0.10))
                                    .matchedGeometryEffect(id: "activeTab", in: tabAnimation)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(.ultraThinMaterial)
            .background(Color(bsHex: 0x11172A, alpha: 0.88))
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(Color(bsHex: 0x262F4A, alpha: 0.85), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .environment(\.colorScheme, .dark)
        .tint(Color(bsHex: 0x7AA2FF))
    }
}
