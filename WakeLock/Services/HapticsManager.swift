import Foundation
import CoreHaptics
import UIKit
import AudioToolbox

/// Drives continuous haptic feedback during alarm punishment phases.
final class HapticsManager {

    static let shared = HapticsManager()
    private init() { prepareEngine() }

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    // MARK: - Public

    func startContinuous() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallbackVibration()
            return
        }
        do {
            try engine?.start()
            let pattern = try continuousPattern()
            player = try engine?.makeAdvancedPlayer(with: pattern)
            player?.loopEnabled = true
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[HapticsManager] Start error: \(error)")
            fallbackVibration()
        }
    }

    func startIntense() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallbackVibration()
            return
        }
        do {
            try engine?.start()
            let pattern = try intensePattern()
            try? player?.stop(atTime: CHHapticTimeImmediate)
            player = try engine?.makeAdvancedPlayer(with: pattern)
            player?.loopEnabled = true
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[HapticsManager] Intense error: \(error)")
        }
    }

    /// Restart the haptic player if the engine was stopped by the OS
    /// (e.g. phone call, lock screen). Pass the same intensity mode that
    /// was active when the alarm started escalating.
    func ensureRunning(intense: Bool) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        guard player == nil else { return }   // already running
        if intense { startIntense() } else { startContinuous() }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        try? engine?.stop()
    }

    // MARK: - Patterns

    private func continuousPattern() throws -> CHHapticPattern {
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [sharpness, intensity],
            relativeTime: 0,
            duration: 1.0
        )
        return try CHHapticPattern(events: [event], parameters: [])
    }

    private func intensePattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        for i in 0..<4 {
            let t = Double(i) * 0.25
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [sharpness, intensity], relativeTime: t)
            events.append(event)
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in
            guard let self else { return }
            // Engine was reset by the OS — restart it and rebuild any active player
            do {
                try self.engine?.start()
            } catch {
                print("[HapticsManager] Engine restart after reset failed: \(error)")
            }
            // If the player existed it is now invalid; clear it so ensureRunning
            // rebuilds it on the next restoreIfNeeded() call from PunishmentEngine.
            self.player = nil
        }
        engine?.stoppedHandler = { reason in
            print("[HapticsManager] Engine stopped: \(reason)")
        }
    }

    private func fallbackVibration() {
        // Simple UIKit vibration for devices without CoreHaptics
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
