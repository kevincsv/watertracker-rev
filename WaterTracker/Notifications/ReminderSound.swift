import AudioToolbox
import AVFoundation
import UserNotifications

/// The sound a reminder plays. The custom sounds are short files bundled
/// with the app (made for it in `scripts/make-sounds.py`), so nothing is
/// downloaded.
nonisolated enum ReminderSound: String, CaseIterable, Identifiable, Sendable {
    case system
    case drop
    case bubbles
    case chime
    case bell
    case wave
    case silent

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: String(localized: "iPhone default")
        case .drop: String(localized: "Drop")
        case .bubbles: String(localized: "Bubbles")
        case .chime: String(localized: "Chime")
        case .bell: String(localized: "Bell")
        case .wave: String(localized: "Wave")
        case .silent: String(localized: "No sound")
        }
    }

    /// The bundled file, for the custom sounds.
    var fileName: String? {
        switch self {
        case .system, .silent: nil
        default: "reminder-\(rawValue).wav"
        }
    }

    var notificationSound: UNNotificationSound? {
        switch self {
        case .system: .default
        case .silent: nil
        default: fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) }
        }
    }
}

/// Plays a sound in Settings so it can be heard before choosing it.
@MainActor
enum SoundPreview {
    private static var player: AVAudioPlayer?

    static func play(_ sound: ReminderSound) {
        player?.stop()
        player = nil
        switch sound {
        case .silent:
            return
        case .system:
            // The standard "new message" tone, the closest stand-in for the default notification sound.
            AudioServicesPlaySystemSound(1007)
        default:
            guard let fileName = sound.fileName,
                  let url = Bundle.main.url(forResource: fileName, withExtension: nil)
            else { return }
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }
    }
}
