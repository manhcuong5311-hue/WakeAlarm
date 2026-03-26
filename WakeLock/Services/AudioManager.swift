import Foundation
import AVFoundation
import AudioToolbox
import Combine

/// Dual-layer persistent alarm audio engine.
///
/// ## Dual-layer design
/// - **Primary layer** (`alarm.caf`): the main loud beeping, always at target volume.
/// - **Secondary layer** (`alarm_aggressive.caf`): starts quiet (0.25), escalates
///   at phase 2 (0.65) and phase 3 (1.0). Offset by 9 seconds to avoid perfect
///   sync with the primary and create a more chaotic, layered soundscape.
///
/// ## Persistence guarantees
/// 1. `AVAudioSession.interruptionNotification` — restarts playback after phone
///    calls, Siri, FaceTime, or any other audio-stealing interruption.
/// 2. `AVAudioSession.routeChangeNotification` — recovers when headphones are
///    unplugged mid-alarm (re-routes to built-in speaker).
/// 3. `AVAudioSession.mediaServicesWereResetNotification` — full reinit after the
///    (rare) media-services daemon reset.
/// 4. **Volume enforcement timer** (every 2 s) — resets `player.volume` to the
///    target value and restarts any player that stopped unexpectedly.
///    `player.volume` is a software multiplier independent of system volume, so
///    this ensures no software-side silencing can persist.
///
/// ## Keepalive
/// A silent loop of `alarm.caf` at volume 0 keeps the process in iOS's
/// "background audio" class while any alarm is armed, so `startAlarm()` fires
/// instantly without a cold-start gap.
final class AudioManager: ObservableObject {

    static let shared = AudioManager()
    private init() { setupSessionObservers() }

    // MARK: - Published state

    /// `true` while the alarm is actively ringing. Observed by the ring UI.
    @Published private(set) var isAlarmPlaying = false

    // MARK: - Players

    private var primaryPlayer: AVAudioPlayer?     // alarm.caf        — main layer
    private var secondaryPlayer: AVAudioPlayer?   // alarm_aggressive — ambient layer
    private var keepalivePlayer: AVAudioPlayer?   // alarm.caf vol=0  — process keepalive

    // MARK: - Timers

    private var rampTimer: Timer?                 // volume ramp for phase 2
    private var enforcementTimer: Timer?          // volume + playback enforcement

    // MARK: - Target volumes (updated by escalation)

    private var primaryTarget: Float  = 0.85      // raised to 1.0 at phase 3
    private var secondaryTarget: Float = 0.25     // 0.25 → 0.65 (phase 2) → 1.0 (phase 3)

    private var sessionActive = false

    // MARK: - Keepalive

    /// Start a silent audio loop so the OS keeps the process in the background-audio
    /// class. Call whenever any alarm is enabled.
    func startKeepalive() {
        guard keepalivePlayer == nil, !isAlarmPlaying else { return }
        activateSession()
        guard let url = soundURL("alarm") else { return }
        do {
            keepalivePlayer = try AVAudioPlayer(contentsOf: url)
            keepalivePlayer?.numberOfLoops = -1
            keepalivePlayer?.volume = 0
            keepalivePlayer?.prepareToPlay()
            keepalivePlayer?.play()
        } catch {
            print("[AudioManager] Keepalive error: \(error)")
        }
    }

    /// Release the keepalive session when all alarms are disabled.
    func stopKeepalive() {
        keepalivePlayer?.stop()
        keepalivePlayer = nil
        if !isAlarmPlaying { deactivateSession() }
    }

    // MARK: - Alarm start

    func startAlarm() {
        guard !isAlarmPlaying else {
            ensurePlaying()   // idempotent — just make sure everything is running
            return
        }

        activateSession()
        primaryTarget   = 0.85
        secondaryTarget = 0.25

        // ── Primary layer ────────────────────────────────────────────────────
        // Reuse the already-running keepalive player for a seamless handoff.
        if let kp = keepalivePlayer {
            kp.volume    = primaryTarget
            primaryPlayer  = kp
            keepalivePlayer = nil
        } else {
            startPrimary(volume: primaryTarget)
        }

        // ── Secondary layer ──────────────────────────────────────────────────
        // Start 9 seconds into the file so it's out of phase with the primary,
        // creating a richer, more disorienting layered texture.
        startSecondary(volume: secondaryTarget, offset: 9.0)

        isAlarmPlaying = true
        startEnforcementTimer()
    }

    // MARK: - Escalation (called by PunishmentEngine)

    /// Phase 2 (30 s): ramp primary to max, jump secondary to 0.65
    func rampToMax() {
        guard isAlarmPlaying else { return }
        secondaryTarget = 0.65
        primaryTarget   = 1.0
        animateToTarget(player: primaryPlayer,   target: primaryTarget)
        animateToTarget(player: secondaryPlayer, target: secondaryTarget)
    }

    /// Phase 3 (60 s): slam both layers to max
    func startAggressiveLayer() {
        guard isAlarmPlaying else { return }
        primaryTarget   = 1.0
        secondaryTarget = 1.0
        primaryPlayer?.volume   = 1.0
        secondaryPlayer?.volume = 1.0
    }

    // MARK: - Recovery (called from scenePhase .active)

    /// Ensure both audio layers are playing. Restarts any player that has
    /// stopped due to an interruption, route change, or OS suspension.
    func ensurePlaying() {
        guard isAlarmPlaying else { return }
        activateSession()

        if let p = primaryPlayer {
            p.volume = primaryTarget
            if !p.isPlaying { p.play() }
        } else {
            startPrimary(volume: primaryTarget)
        }

        if let s = secondaryPlayer {
            s.volume = secondaryTarget
            if !s.isPlaying { s.play() }
        } else {
            startSecondary(volume: secondaryTarget, offset: 0)
        }
    }

    // MARK: - Stop

    func stopAlarm() {
        isAlarmPlaying  = false
        primaryTarget   = 0.85
        secondaryTarget = 0.25

        enforcementTimer?.invalidate(); enforcementTimer = nil
        rampTimer?.invalidate();        rampTimer        = nil

        primaryPlayer?.stop();   primaryPlayer   = nil
        secondaryPlayer?.stop(); secondaryPlayer = nil

        // Rearm keepalive if any alarm is still enabled
        if AlarmManager.shared.alarms.contains(where: { $0.isEnabled }) {
            startKeepalive()
        } else {
            deactivateSession()
        }
    }

    // MARK: - Private: player construction

    private func startPrimary(volume: Float) {
        guard let url = soundURL("alarm") else {
            AudioServicesPlaySystemSound(1005)
            return
        }
        do {
            primaryPlayer = try AVAudioPlayer(contentsOf: url)
            primaryPlayer?.numberOfLoops = -1
            primaryPlayer?.volume        = volume
            primaryPlayer?.prepareToPlay()
            primaryPlayer?.play()
        } catch {
            print("[AudioManager] Primary play error: \(error)")
        }
    }

    private func startSecondary(volume: Float, offset: TimeInterval) {
        guard let url = soundURL("alarm_aggressive") ?? soundURL("alarm") else { return }
        do {
            secondaryPlayer = try AVAudioPlayer(contentsOf: url)
            secondaryPlayer?.numberOfLoops  = -1
            secondaryPlayer?.volume         = volume
            secondaryPlayer?.currentTime    = offset  // phase offset for layered texture
            secondaryPlayer?.prepareToPlay()
            secondaryPlayer?.play()
        } catch {
            print("[AudioManager] Secondary play error: \(error)")
        }
    }

    // MARK: - Private: volume ramp

    private func animateToTarget(player: AVAudioPlayer?, target: Float) {
        guard let player else { return }
        var v = player.volume
        rampTimer?.invalidate()
        rampTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] t in
            guard self != nil else { t.invalidate(); return }
            v = min(v + 0.05, target)
            player.volume = v
            if v >= target { t.invalidate() }
        }
    }

    // MARK: - Private: enforcement timer

    /// Fires every 2 seconds to:
    /// 1. Reset `player.volume` to its target (counteracts any software-level reduction)
    /// 2. Restart a player that stopped unexpectedly (OS-driven pause, session hiccup)
    private func startEnforcementTimer() {
        enforcementTimer?.invalidate()
        enforcementTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.enforcePlayback()
        }
    }

    private func enforcePlayback() {
        guard isAlarmPlaying else { return }

        // Enforce software volumes regardless of what interrupted them
        primaryPlayer?.volume   = primaryTarget
        secondaryPlayer?.volume = secondaryTarget

        // Restart players that were stopped by the OS
        if let p = primaryPlayer, !p.isPlaying {
            activateSession()
            p.play()
        }
        if let s = secondaryPlayer, !s.isPlaying {
            s.play()
        }
    }

    // MARK: - Private: session

    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            print("[AudioManager] Session activate error: \(error)")
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    // MARK: - Private: notification observers

    private func setupSessionObservers() {
        let center = NotificationCenter.default

        // ── Interruption (phone calls, Siri, FaceTime, etc.) ─────────────────
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        // ── Route change (headphones unplugged) ───────────────────────────────
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        // ── Media services reset (rare daemon crash) ──────────────────────────
        center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }

        switch type {
        case .began:
            // OS has paused our audio (e.g. incoming call) — nothing to do,
            // the enforcement timer will detect the stopped players and restart on .ended
            print("[AudioManager] Session interrupted")

        case .ended:
            // Interruption is over (call ended, Siri dismissed, etc.)
            let opts = AVAudioSession.InterruptionOptions(
                rawValue: (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            )
            if opts.contains(.shouldResume) {
                // Small delay to let the OS fully release the audio focus
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.ensurePlaying()
                }
            }

        @unknown default: break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isAlarmPlaying,
              let info = notification.userInfo,
              let reasonVal = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonVal) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged — iOS pauses playback; restart on speaker
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.ensurePlaying()
            }
        case .categoryChange:
            // Category was changed under us — reactivate and resume
            sessionActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.ensurePlaying()
            }
        default: break
        }
    }

    private func handleMediaServicesReset() {
        // Full media-services daemon reset — all players and sessions are invalid.
        // Discard everything and start fresh.
        sessionActive     = false
        primaryPlayer     = nil
        secondaryPlayer   = nil
        keepalivePlayer   = nil

        if isAlarmPlaying {
            isAlarmPlaying = false   // reset guard so startAlarm() runs fully
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startAlarm()
            }
        }
    }

    // MARK: - Private: sound file lookup

    private func soundURL(_ name: String) -> URL? {
        for ext in ["caf", "m4a", "wav", "mp3"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        }
        // Last-resort system sound
        let path = "/System/Library/Audio/UISounds/alarm.caf"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}
