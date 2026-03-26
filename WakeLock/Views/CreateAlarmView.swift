import SwiftUI

struct CreateAlarmView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: CreateAlarmViewModel

    init(editing alarm: Alarm? = nil) {
        _vm = StateObject(wrappedValue: CreateAlarmViewModel(editing: alarm))
    }

    private let weekdays = ["S","M","T","W","T","F","S"]
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Large time wheel — the centrepiece
                        timePickerSection
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 16)

                        // Label
                        labelSection
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 16)
                            .animation(DS.Animation.spring.delay(0.08), value: appear)

                        // Repeat
                        repeatSection
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 16)
                            .animation(DS.Animation.spring.delay(0.12), value: appear)

                        // Dismiss method
                        dismissSection
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 16)
                            .animation(DS.Animation.spring.delay(0.16), value: appear)

                        Spacer().frame(height: 8)

                        // Save CTA
                        PrimaryButton(vm.editingAlarm == nil ? "Create Alarm" : "Save Changes",
                                      icon: "checkmark") {
                            guard vm.requiresQR || vm.allowsBiometrics else { return }
                            vm.save()
                            dismiss()
                        }
                        .disabled(!vm.isValid || (!vm.requiresQR && !vm.allowsBiometrics))
                        .padding(.horizontal, DS.Layout.screenPadding)
                        .opacity(appear ? 1 : 0)
                        .animation(DS.Animation.spring.delay(0.2), value: appear)

                        Spacer().frame(height: 32)
                    }
                }
            }
            .navigationTitle(vm.editingAlarm == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Color.accent)
                }
            }
        }
        .onAppear {
            withAnimation(DS.Animation.spring.delay(0.05)) { appear = true }
        }
    }

    // MARK: - Sections

    private var timePickerSection: some View {
        ZStack {
            // Card bg
            Color.appSurface
                .clipShape(RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .continuous))
                .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, y: DS.Shadow.card.y)

            DatePicker("", selection: $vm.selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .scaleEffect(1.08)
                .padding(.vertical, 8)
        }
        .frame(height: 220)
        .padding(.horizontal, DS.Layout.screenPadding)
        .animation(DS.Animation.spring, value: appear)
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Label")

            HStack(spacing: 12) {
                Image(systemName: "tag")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.label2)
                TextField("e.g. Morning Workout", text: $vm.label)
                    .font(DS.Font.body)
            }
            .padding(DS.Layout.cardPadding)
            .cardStyle()
        }
        .padding(.horizontal, DS.Layout.screenPadding)
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Repeat")

            // Repeat mode pills – horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AlarmRepeat.allCases, id: \.self) { p in
                        repeatPill(p)
                    }
                }
                .padding(.horizontal, DS.Layout.screenPadding)
            }

            // Custom day grid (only when custom selected)
            if vm.repeatPattern == .custom {
                customDayRow
                    .padding(.horizontal, DS.Layout.screenPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DS.Animation.snappy, value: vm.repeatPattern)
    }

    private func repeatPill(_ p: AlarmRepeat) -> some View {
        let selected = vm.repeatPattern == p
        return Button { withAnimation(DS.Animation.snappy) { vm.repeatPattern = p } } label: {
            Text(p.rawValue)
                .font(DS.Font.captionBold)
                .tracking(0.3)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(selected ? DS.Color.accent : Color.appSurface)
                .foregroundStyle(selected ? .white : DS.Color.label2)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: selected ? DS.Shadow.button.color : .clear,
                        radius: selected ? 8 : 0, y: 3)
        }
        .buttonStyle(PressEffectButtonStyle())
    }

    private var customDayRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { idx in
                let day = idx + 1
                let selected = vm.customDays.contains(day)
                Button {
                    withAnimation(DS.Animation.snappy) {
                        if selected { vm.customDays.remove(day) }
                        else { vm.customDays.insert(day) }
                    }
                } label: {
                    Text(weekdays[idx])
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selected ? DS.Color.accent : Color.appSurface)
                        .foregroundStyle(selected ? .white : DS.Color.label2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? .clear : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(PressEffectButtonStyle())
            }
        }
    }

    private var dismissSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Dismiss Method")

            VStack(spacing: 0) {
                dismissToggleRow(
                    icon: "qrcode.viewfinder",
                    iconColor: DS.Color.success,
                    title: "Require QR Scan",
                    isOn: $vm.requiresQR
                )

                Divider().padding(.leading, 60).opacity(0.5)

                dismissToggleRow(
                    icon: "faceid",
                    iconColor: DS.Color.accent,
                    title: "Allow Face ID / Touch ID",
                    isOn: $vm.allowsBiometrics
                )
            }
            .cardStyle()

            if !vm.requiresQR && !vm.allowsBiometrics {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("At least one dismiss method must be enabled.")
                }
                .font(DS.Font.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.Layout.screenPadding)
        .animation(DS.Animation.snappy, value: vm.requiresQR && vm.allowsBiometrics)
    }

    private func dismissToggleRow(icon: String, iconColor: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(DS.Font.body)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DS.Color.accent)
        }
        .padding(DS.Layout.cardPadding)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.captionBold)
            .foregroundStyle(DS.Color.label2)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 4)
    }
}

#Preview {
    CreateAlarmView()
}
