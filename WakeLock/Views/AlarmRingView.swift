import SwiftUI
import Combine
// MARK: - Alarm Ring View

struct AlarmRingView: View {

    @StateObject var vm: AlarmRingViewModel
    @ObservedObject private var punishment = PunishmentEngine.shared

    @State private var clockScale: CGFloat = 1.0
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.5
    @State private var isFlashing: Bool = false
    @State private var shakeOffset: CGFloat = 0
    @State private var appear: Bool = false

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()
                .animation(DS.Animation.crossfade, value: punishment.phase)

            RadialGradient(
                colors: [glowColor.opacity(0.18), glowColor.opacity(0.06), .clear],
                center: .center, startRadius: 40, endRadius: 260
            )
            .ignoresSafeArea()
            .animation(DS.Animation.crossfade, value: punishment.phase)

            if punishment.phase.rawValue >= 2 {
                Color.red
                    .opacity(isFlashing ? 0.12 : 0.0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(DS.Animation.pulse(0.6), value: isFlashing)
            }

            VStack(spacing: 0) {
                Spacer()
                pulseRingsView
                Spacer()

                if punishment.phase == .phase3 {
                    urgentBanner
                        .padding(.horizontal, DS.Layout.screenPadding)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
                clockView.offset(x: shakeOffset)
                Spacer()

                dismissButtons
                    .padding(.horizontal, DS.Layout.screenPadding)
                    .padding(.bottom, 56)
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            startPulseAnimations()
            withAnimation(DS.Animation.spring.delay(0.1)) { appear = true }
        }
        .onChange(of: punishment.phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .onChange(of: punishment.elapsedSeconds) { _, _ in
            tickClock()
        }
        .sheet(isPresented: $vm.showQRScanner) {
            QRDismissSheet(vm: vm).interactiveDismissDisabled(true)
        }
        .alert("Authentication Failed",
               isPresented: Binding(
                get: { vm.biometricError != nil },
                set: { if !$0 { vm.biometricError = nil } }
               )) {
            Button("Try Again", role: .cancel) { vm.biometricError = nil }
        } message: {
            Text(vm.biometricError ?? "")
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private var backgroundGradient: some View {
        switch punishment.phase {
        case .phase1: DS.Gradient.alarmRingPhase1
        case .phase2: DS.Gradient.alarmRingPhase2
        case .phase3: DS.Gradient.alarmRingPhase3
        }
    }

    private var glowColor: Color {
        switch punishment.phase {
        case .phase1: return Color(hex: "4A90E2")
        case .phase2: return DS.Color.danger
        case .phase3: return DS.Color.danger
        }
    }

    // MARK: - Pulse rings

    private var pulseRingsView: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(glowColor.opacity(0.12 - Double(i) * 0.03), lineWidth: 1)
                    .scaleEffect(ringScale + CGFloat(i) * 0.18)
                    .opacity(ringOpacity - Double(i) * 0.1)
                    .frame(width: 200, height: 200)
                    .animation(DS.Animation.pulse(1.2 + Double(i) * 0.3), value: ringScale)
            }
        }
        .frame(height: 0)
    }

    // MARK: - Clock

    private var clockView: some View {
        VStack(spacing: 10) {
            Text(currentTimeString)
                .font(.system(size: 76, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: glowColor.opacity(0.5), radius: 20, y: 0)
                .scaleEffect(clockScale)
                .animation(.easeInOut(duration: 0.25), value: clockScale)

            Text(vm.alarm.label.isEmpty ? "Wake up." : vm.alarm.label)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1)

            if punishment.phase.rawValue >= 2 {
                elapsedPill.transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(appear ? 1 : 0.85)
        .opacity(appear ? 1 : 0)
    }

    private var elapsedPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.Color.danger)
                .frame(width: 6, height: 6)
                .opacity(isFlashing ? 1 : 0.3)
                .animation(DS.Animation.pulse(0.7), value: isFlashing)
            Text("\(punishment.elapsedSeconds)s")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Color.danger)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(DS.Color.danger.opacity(0.15))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Color.danger.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Urgent banner (phase 3)

    private var urgentBanner: some View {
        VStack(spacing: 6) {
            Text("GET UP NOW")
                .font(.system(size: 13, weight: .black))
                .tracking(3)
                .foregroundStyle(DS.Color.danger)
            Text("You are losing your morning.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(DS.Color.danger.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Color.danger.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Dismiss buttons

    private var dismissButtons: some View {
        VStack(spacing: 14) {
            if vm.alarm.requiresQR {
                PulsingBorderButton(
                    title: "Scan QR to Stop",
                    icon: "qrcode.viewfinder",
                    pulseColor: punishment.phase == .phase1 ? .white : DS.Color.danger,
                    action: vm.dismissViaQR
                )
            }

            if vm.alarm.allowsBiometrics && vm.biometricAvailable {
                Button { vm.dismissViaBiometrics() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "faceid")
                            .font(.system(size: 16, weight: .medium))
                        Text("Use Face ID")
                            .font(DS.Font.bodyBold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Layout.buttonHeight)
                    .foregroundStyle(.white.opacity(0.85))
                    .background(.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(PressEffectButtonStyle())
            }
        }
    }

    // MARK: - Animation

    private func startPulseAnimations() {
        withAnimation(DS.Animation.pulse(1.4)) {
            ringScale = 1.3
            ringOpacity = 0.0
        }
    }

    private func handlePhaseChange(_ phase: PunishmentPhase) {
        if phase.rawValue >= 2 { isFlashing = true }
        if phase == .phase3 { startShaking() }
        withAnimation(DS.Animation.pulse(phase == .phase3 ? 0.6 : 1.0)) { ringScale = 1.3 }
    }

    private func tickClock() {
        clockScale = 1.04
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { clockScale = 1.0 }
    }

    private func startShaking() {
        let values: [CGFloat] = [0, -6, 6, -4, 4, -2, 2, 0]
        for (i, v) in values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(.easeInOut(duration: 0.06)) { shakeOffset = v }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if PunishmentEngine.shared.phase == .phase3 { startShaking() }
        }
    }

    private var currentTimeString: String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: Date())
    }
}

// MARK: - Pulsing Border Button

struct PulsingBorderButton: View {
    let title: String
    let icon: String
    let pulseColor: Color
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(DS.Font.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DS.Layout.buttonHeight)
            .foregroundStyle(Color(hex: "0D0D0D"))
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(pulseColor.opacity(pulse ? 0.9 : 0.2), lineWidth: pulse ? 2 : 1)
                    .animation(DS.Animation.pulse(1.0), value: pulse)
            )
            .shadow(
                color: pulseColor.opacity(pulse ? 0.5 : 0.2),
                radius: pulse ? 18 : 8, y: 4
            )
            .animation(DS.Animation.pulse(1.0), value: pulse)
        }
        .buttonStyle(PressEffectButtonStyle())
        .onAppear { pulse = true }
    }
}

// MARK: - QR Dismiss Sheet

struct QRDismissSheet: View {
    @ObservedObject var vm: AlarmRingViewModel
    @StateObject private var scanVM = QRScanViewModel(mode: .dismiss)

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text("Scan QR Code")
                        .font(DS.Font.sectionTitle)
                        .foregroundStyle(.white)
                    Text("Find the QR code you placed far from your bed")
                        .font(DS.Font.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, DS.Layout.screenPadding)
                .padding(.bottom, 20)

                if scanVM.cameraPermissionGranted {
                    QRScannerView { scanVM.handleScanned(value: $0) }
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "camera.slash.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(DS.Color.danger)
                        Text("Camera access denied.\nUse Face ID to dismiss your alarm.")
                            .font(DS.Font.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                }

                if case .failure(let msg) = scanVM.result {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Color.danger)
                        Text(msg).font(DS.Font.captionBold).foregroundStyle(DS.Color.danger)
                    }
                    .padding(.vertical, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onChange(of: scanVM.result) { _, r in if case .success = r { vm.onQRSuccess() } }
        .onAppear { scanVM.result = .scanning }
    }
}
