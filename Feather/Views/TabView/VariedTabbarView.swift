import SwiftUI

/// Turath's navigation shell, kept visually identical while every destination
/// is backed by BatSign's real engine and data.
struct VariedTabbarView: View {
    @State private var selected: TurathTab = .home
    @State private var splashVisible = true

    init() {}

    var body: some View {
        ZStack {
            TurathShell(selected: $selected)
                .opacity(splashVisible ? 0 : 1)

            if splashVisible {
                TurathSplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
        }
        .background(TurathPalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(TurathPalette.accent)
        .task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeInOut(duration: 0.42)) { splashVisible = false }
        }
    }
}

private enum TurathPalette {
    static let accent = Color(bsHex: 0x7AA2FF)
    static let background = Color(bsHex: 0x0B1020)
    static let surface = Color(bsHex: 0x151B2E)
    static let border = Color(bsHex: 0x262F4A)
    static let sheet = Color(bsHex: 0x11172A)
    static let text = Color(bsHex: 0xF2F4FA)
    static let secondary = Color(bsHex: 0x9AA3BC)
    static let inactive = Color(bsHex: 0x7B84A1)
    static let splash = Color(bsHex: 0x011D57)
}

private enum TurathTab: String, CaseIterable, Identifiable {
    case home = "الرئيسية"
    case explore = "استكشف"
    case updates = "التحديثات"
    case shop = "المتجر"
    case search = "البحث"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "square.grid.2x2.fill"
        case .updates: return "arrow.triangle.2.circlepath"
        case .shop: return "bag.fill"
        case .search: return "magnifyingglass"
        }
    }
}

private struct TurathShell: View {
    @Binding var selected: TurathTab

    var body: some View {
        ZStack(alignment: .bottom) {
            TurathPalette.background.ignoresSafeArea()

            Group {
                switch selected {
                case .home:
                    DiscoverView()
                case .explore:
                    BSAppsView(title: "استكشف")
                case .updates:
                    UpdatesView()
                case .shop:
                    LibraryView()
                case .search:
                    BSAppsView(title: "البحث")
                }
            }
            .padding(.bottom, 84)

            TurathFloatingTabBar(selected: $selected)
        }
    }
}

private struct TurathFloatingTabBar: View {
    @Binding var selected: TurathTab
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TurathTab.allCases) { tab in
                Button {
                    BSHaptics.tap()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selected = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected == tab ? TurathPalette.accent : TurathPalette.inactive)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if selected == tab {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(TurathPalette.accent.opacity(0.10))
                                .matchedGeometryEffect(id: "active", in: animation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .frame(maxWidth: 460)
        .background(.ultraThinMaterial)
        .background(TurathPalette.sheet.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(TurathPalette.border.opacity(0.85), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

private struct TurathSplashView: View {
    @State private var breathe = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            TurathPalette.splash.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.13), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 270
            )
            .scaleEffect(breathe ? 1.18 : 0.88)
            .opacity(breathe ? 0.8 : 0.45)

            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 118, height: 118)
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        .frame(width: 118, height: 118)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(breathe ? 1.04 : 0.96)

                VStack(spacing: 9) {
                    Text("التراث بلس")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("أقوى متجر لتطبيقات البلس والاشتراكات الرقمية")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.74))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 110, height: 600)
                .rotationEffect(.degrees(17))
                .offset(x: sweep ? 300 : -300)
                .blur(radius: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}
