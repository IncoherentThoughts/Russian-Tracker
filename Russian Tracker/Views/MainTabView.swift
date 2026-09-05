import SwiftUI

enum Tab: Int, CaseIterable {
    case stats    = 0
    case timer    = 1
    case settings = 2

    var icon: String {
        switch self {
        case .stats:    return "chart.bar"
        case .timer:    return "timer"
        case .settings: return "person"
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: Tab = .timer
    #if os(macOS)
    /// Optional so previews and tests work without the app injecting it.
    @Environment(WindowNavigation.self) private var navigation: WindowNavigation?
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            // Native paging gives interactive drag-with-snap: you can hold,
            // drag halfway, and release to snap to whichever side you're
            // majority on. Vertical scrolling inside child views still works
            // because TabView only claims horizontal pans.
            pages

            FloatingTabBar(selectedTab: $selectedTab)
                .padding(.bottom, 22)
        }
        .background(Color.eggshell.ignoresSafeArea())
        #if os(macOS)
        // ⌘1/⌘2/⌘3 arrive through `WindowNavigation`; clicks on the capsule
        // bar are reported back so the Go menu's checkmark follows.
        .onAppear { if let tab = navigation?.selectedTab { selectedTab = tab } }
        .onChange(of: navigation?.selectedTab) { _, tab in
            guard let tab, tab != selectedTab else { return }
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        }
        .onChange(of: selectedTab) { _, tab in
            if navigation?.selectedTab != tab { navigation?.selectedTab = tab }
        }
        #endif
    }
}

// MARK: - Pages

private extension MainTabView {
    /// iOS keeps the native paging TabView (interactive drag-with-snap).
    /// macOS has no page style, so the three screens swap in place with a
    /// short slide instead; navigation there is the tab bar and ⌘1/⌘2/⌘3.
    @ViewBuilder
    var pages: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            StatsView().tag(Tab.stats)
            TimerView().tag(Tab.timer)
            SettingsView().tag(Tab.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard)
        #else
        ZStack {
            switch selectedTab {
            case .stats:    StatsView().transition(.move(edge: .leading).combined(with: .opacity))
            case .timer:    TimerView().transition(.opacity)
            case .settings: SettingsView().transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedTab)
        #endif
    }
}

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach([Tab.stats, .timer, .settings], id: \.self) { tab in
                TabButton(tab: tab, selectedTab: $selectedTab)
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.eggshell.opacity(0.35)))
        )
        .overlay(
            Capsule().stroke(Color.hairline, lineWidth: 1)
        )
        .shadow(color: Color.toffeeBrown.opacity(0.18), radius: 18, x: 0, y: 12)
        .shadow(color: Color.toffeeBrown.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

private struct TabButton: View {
    let tab: Tab
    @Binding var selectedTab: Tab

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(isSelected ? .toffeeInk : .bronzeMuted)

                // Active indicator dot
                VStack {
                    Spacer()
                    Circle()
                        .fill(Color.rosyCopper)
                        .frame(width: 4, height: 4)
                        .opacity(isSelected ? 1 : 0)
                        .padding(.bottom, 4)
                }
            }
            .frame(width: 56, height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
        .environment(TimerManager())
        .environment(StudyStore())
}
