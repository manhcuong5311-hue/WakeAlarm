import SwiftUI

// MARK: - Design Tokens

enum DS {

    // MARK: Colors

    enum Color {
        /// Primary accent – blue
        static let accent       = SwiftUI.Color(hex: "4A90E2")
        /// Alarm danger state
        static let danger       = SwiftUI.Color(hex: "FF3B30")
        /// Streak orange
        static let streak       = SwiftUI.Color(hex: "FF9500")
        /// Success green
        static let success      = SwiftUI.Color(hex: "34C759")
        /// Muted label
        static let label2       = SwiftUI.Color.primary.opacity(0.55)
        static let label3       = SwiftUI.Color.primary.opacity(0.35)
    }

    // MARK: Gradients

    enum Gradient {
        static let accent = LinearGradient(
            colors: [SwiftUI.Color(hex: "4A90E2"), SwiftUI.Color(hex: "7B5EA7")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let streakCard = LinearGradient(
            colors: [SwiftUI.Color(hex: "FF9500").opacity(0.18), SwiftUI.Color(hex: "FF6B00").opacity(0.06)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let alarmRingPhase1 = LinearGradient(
            colors: [SwiftUI.Color(hex: "0D0D0D"), SwiftUI.Color(hex: "131320")],
            startPoint: .top, endPoint: .bottom
        )
        static let alarmRingPhase2 = LinearGradient(
            colors: [SwiftUI.Color(hex: "1A0000"), SwiftUI.Color(hex: "2D0000")],
            startPoint: .top, endPoint: .bottom
        )
        static let alarmRingPhase3 = LinearGradient(
            colors: [SwiftUI.Color(hex: "3D0000"), SwiftUI.Color(hex: "1A0000")],
            startPoint: .top, endPoint: .bottom
        )
        static let successGlow = RadialGradient(
            colors: [SwiftUI.Color(hex: "34C759").opacity(0.3), .clear],
            center: .center, startRadius: 0, endRadius: 120
        )
    }

    // MARK: Typography

    enum Font {
        static func ringClock(_ size: CGFloat = 80) -> SwiftUI.Font {
            .system(size: size, weight: .thin, design: .rounded)
        }
        static let alarmTime    = SwiftUI.Font.system(size: 40, weight: .light, design: .rounded)
        static let sectionTitle = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let greeting     = SwiftUI.Font.system(size: 28, weight: .bold)
        static let body         = SwiftUI.Font.system(size: 17, weight: .regular)
        static let bodyBold     = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let caption      = SwiftUI.Font.system(size: 13, weight: .regular)
        static let captionBold  = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let label        = SwiftUI.Font.system(size: 15, weight: .regular)
        static let headline     = SwiftUI.Font.system(size: 17, weight: .semibold)
    }

    // MARK: Layout

    enum Layout {
        static let screenPadding: CGFloat  = 20
        static let cardRadius: CGFloat     = 24
        static let cardPadding: CGFloat    = 20
        static let buttonHeight: CGFloat   = 58
        static let smallButtonHeight: CGFloat = 44
        static let sectionSpacing: CGFloat = 24
        static let itemSpacing: CGFloat    = 12
    }

    // MARK: Shadows

    enum Shadow {
        static let card    = (color: SwiftUI.Color.black.opacity(0.07), radius: CGFloat(20), y: CGFloat(6))
        static let button  = (color: SwiftUI.Color(hex: "4A90E2").opacity(0.35), radius: CGFloat(14), y: CGFloat(6))
        static let danger  = (color: SwiftUI.Color(hex: "FF3B30").opacity(0.45), radius: CGFloat(16), y: CGFloat(6))
        static let streak  = (color: SwiftUI.Color(hex: "FF9500").opacity(0.3),  radius: CGFloat(18), y: CGFloat(4))
    }

    // MARK: Animation

    enum Animation {
        /// Default spring for UI transitions
        static let spring    = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        /// Snappy spring for toggle/selection feedback
        static let snappy    = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.75)
        /// Smooth easeInOut for modal transitions
        static let smooth    = SwiftUI.Animation.easeInOut(duration: 0.3)
        /// Gentle background crossfade
        static let crossfade = SwiftUI.Animation.easeInOut(duration: 0.6)
        /// Alarm pulse
        static func pulse(_ duration: Double = 0.9) -> SwiftUI.Animation {
            .easeInOut(duration: duration).repeatForever(autoreverses: true)
        }
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Adaptive surface colors
// These use UIColor for automatic light/dark switching

extension Color {
    static var appBackground: Color {
        Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1)  // #0D0D0D
                : UIColor(red: 0.973, green: 0.973, blue: 0.973, alpha: 1)  // #F8F8F8
        })
    }
    static var appSurface: Color {
        Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1)  // #1A1A1C
                : UIColor.white
        })
    }
    static var appSurface2: Color {
        Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.141, green: 0.141, blue: 0.149, alpha: 1)  // #242426
                : UIColor(red: 0.937, green: 0.937, blue: 0.945, alpha: 1)  // #EFEFF1
        })
    }
}

// MARK: - Button press modifier

struct PressEffectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(DS.Animation.snappy, value: configuration.isPressed)
    }
}

// MARK: - View helpers

extension View {
    func cardStyle() -> some View {
        self
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .continuous))
            .shadow(color: DS.Shadow.card.color,
                    radius: DS.Shadow.card.radius,
                    y: DS.Shadow.card.y)
    }

}
