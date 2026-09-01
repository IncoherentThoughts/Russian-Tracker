import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Russian Timer Palette
    static let toffeeBrown   = Color(hex: "#9E6240")  // primary text, icons
    static let toffeeInk     = Color(hex: "#7A4A2E")  // deeper variant for display numerals + primary text
    static let lightBronze   = Color(hex: "#DEA47E")  // muted inline elements
    static let bronzeMuted   = Color(hex: "#C89573")  // muted body labels / eyebrows
    static let rosyCopper    = Color(hex: "#CD4631")  // active states, progress, accents
    static let copperSoft    = Color(hex: "#E5735F")  // soft copper for ring backdrops
    static let eggshell      = Color(hex: "#F8F2DC")  // app background
    static let eggshellDeep  = Color(hex: "#F3EACD")  // card background — warm parchment
    static let skyReflection = Color(hex: "#81ADC8")  // achievement callouts (Best Day)

    static let hairline       = Color.toffeeBrown.opacity(0.15)
    static let hairlineStrong = Color.toffeeBrown.opacity(0.25)
}

// MARK: - Typography helpers

extension Text {
    /// Eyebrow label — small uppercase tracked label used above stat cards, in tab bars, etc.
    func eyebrowStyle(color: Color = .bronzeMuted) -> some View {
        self
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.47)
            .textCase(.uppercase)
            .foregroundColor(color)
    }

    /// Page title — "Statistics", "Settings"
    func pageTitleStyle() -> some View {
        self
            .font(.system(size: 34, weight: .light))
            .tracking(-1.02)
            .foregroundColor(.toffeeInk)
    }

    /// Section header inside a card — "Last 7 days", "All-time"
    func sectionHeaderStyle() -> some View {
        self
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.17)
            .foregroundColor(.toffeeInk)
    }
}
