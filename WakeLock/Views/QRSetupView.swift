import SwiftUI

struct QRSetupView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var qrManager = QRManager.shared

    @State private var step: SetupStep = .intro
    @State private var labelText: String = "Bathroom"
    @State private var scannedValue: String? = nil
    @State private var iconBounce = false

    enum SetupStep: Int { case intro, label, scan, done }

    var body: some View {
        ZStack {
            Color(hex: "0D0D0D").ignoresSafeArea()

            switch step {
            case .intro: introView
            case .label: labelView
            case .scan:  scanView
            case .done:  doneView
            }
        }
        .statusBarHidden()
        .animation(.easeInOut(duration: 0.35), value: step)
    }

    // MARK: - Step 1: Intro

    private var introView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated icon
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(DS.Color.success.opacity(0.15), lineWidth: 1)
                    .frame(width: 140, height: 140)
                    .scaleEffect(iconBounce ? 1.12 : 1.0)
                    .animation(DS.Animation.pulse(2.0), value: iconBounce)

                Circle()
                    .fill(DS.Color.success.opacity(0.08))
                    .frame(width: 110, height: 110)

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(DS.Color.success)
                    .scaleEffect(iconBounce ? 1.06 : 1.0)
                    .animation(DS.Animation.pulse(2.0), value: iconBounce)
            }
            .onAppear { iconBounce = true }

            Spacer().frame(height: 48)

            VStack(spacing: 12) {
                Text("Set Up Your\nQR Code")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Place it far from your bed.\nYou must walk to it to silence your alarm.")
                    .font(DS.Font.body)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer().frame(height: 48)

            // Rule callout
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.lock.fill")
                    .foregroundStyle(DS.Color.streak)
                    .font(.system(size: 15, weight: .semibold))
                Text("There is no other way to turn off the alarm.")
                    .font(DS.Font.captionBold)
                    .foregroundStyle(DS.Color.streak)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(DS.Color.streak.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DS.Color.streak.opacity(0.2), lineWidth: 1))

            Spacer()

            // CTA
            PrimaryButton("Get Started", icon: "arrow.right") {
                withAnimation { step = .label }
            }
            .padding(.horizontal, DS.Layout.screenPadding)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Label

    private var labelView: some View {
        VStack(spacing: 0) {
            // Back + progress
            topBar(title: "Location", stepIndex: 2)

            Spacer()

            VStack(spacing: 8) {
                Text("Where will you\nplace it?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Pick a spot far enough to make you get up.")
                    .font(DS.Font.label)
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 40)

            // Location chips
            VStack(spacing: 10) {
                ForEach(["Bathroom", "Kitchen", "Front Door", "Desk"], id: \.self) { loc in
                    locationChip(loc)
                }
            }
            .padding(.horizontal, DS.Layout.screenPadding)

            Spacer().frame(height: 16)

            // Custom text input
            HStack(spacing: 12) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Custom location…", text: $labelText)
                    .font(DS.Font.body)
                    .foregroundStyle(.white)
                    .tint(DS.Color.success)
            }
            .padding(DS.Layout.cardPadding)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, DS.Layout.screenPadding)

            Spacer()

            PrimaryButton("Next — Scan QR", icon: "qrcode.viewfinder") {
                withAnimation { step = .scan }
            }
            .padding(.horizontal, DS.Layout.screenPadding)
            .padding(.bottom, 48)
        }
    }

    private func locationChip(_ location: String) -> some View {
        let selected = labelText == location
        return Button {
            withAnimation(DS.Animation.snappy) { labelText = location }
        } label: {
            HStack {
                Text(location)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(selected ? Color(hex: "0D0D0D") : .white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "0D0D0D"))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(DS.Layout.cardPadding)
            .background(selected ? DS.Color.success : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? .clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PressEffectButtonStyle())
    }

    // MARK: - Step 3: Scan

    private var scanView: some View {
        ZStack {
            // Full camera preview
            QRScannerView { value in
                withAnimation { scannedValue = value; step = .done }
            }
            .ignoresSafeArea()

            // Overlay
            VStack {
                topBar(title: "Scan", stepIndex: 3)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "0D0D0D"), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )

                Spacer()

                // Viewfinder label
                VStack(spacing: 8) {
                    Text("Point at your QR code")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(.white)
                    Text("Place it somewhere that forces you to get up")
                        .font(DS.Font.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 56)
            }
        }
    }

    // MARK: - Step 4: Done

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Success icon with glow
            ZStack {
                DS.Gradient.successGlow.frame(width: 240, height: 240)
                Circle().fill(DS.Color.success.opacity(0.12)).frame(width: 110, height: 110)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(DS.Color.success)
                    .shadow(color: DS.Color.success.opacity(0.5), radius: 20, y: 0)
            }

            Spacer().frame(height: 40)

            VStack(spacing: 8) {
                Text("QR Code Saved")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text("📍 \(labelText)")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.success)
                if let v = scannedValue {
                    Text(String(v.prefix(36)) + (v.count > 36 ? "…" : ""))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton("Start Creating Alarms", icon: "alarm.fill") {
                    if let v = scannedValue { QRManager.shared.add(label: labelText, value: v) }
                    dismiss()
                }

                GhostButton("Scan Another QR Code") {
                    scannedValue = nil
                    withAnimation { step = .label }
                }
            }
            .padding(.horizontal, DS.Layout.screenPadding)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Shared chrome

    private func topBar(title: String, stepIndex: Int) -> some View {
        HStack {
            Button {
                withAnimation { self.step = SetupStep(rawValue: stepIndex - 2) ?? .intro }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(PressEffectButtonStyle())

            Spacer()

            // Step dots
            HStack(spacing: 6) {
                ForEach(1..<5) { i in
                    Circle()
                        .fill(i == stepIndex ? DS.Color.success : Color.white.opacity(0.2))
                        .frame(width: i == stepIndex ? 20 : 6, height: 6)
                        .clipShape(Capsule())
                        .animation(DS.Animation.spring, value: stepIndex)
                }
            }

            Spacer()

            // Placeholder for balance
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, DS.Layout.screenPadding)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    QRSetupView()
}
