import Foundation
import AVFoundation
import AudioToolbox

// MARK: - VoiceGuide
//
// Giọng nói tiếng Việt cho chỉ đường + cảnh báo (P1 — xem docs/NAV-PRO-DESIGN.md §7).
// AVSpeechSynthesizer gói trong @MainActor ObservableObject để lifecycle bằng
// với MapScreen (root view — sống suốt app, tránh lỗi synthesizer bị dealloc
// giữa chừng). Một utterance tại một thời điểm: chỉ đường luôn được ưu tiên
// (speak() mới ngắt utterance cũ).

@MainActor
final class VoiceGuide: ObservableObject {
    private let synth = AVSpeechSynthesizer()
    private var configured = false
    private(set) var lastSpoken: String?

    init() {
        // Delegate tĩnh: iOS cần delegate sống lâu hơn synthesizer, nếu không
        // speak có thể dừng đột ngột (bug kinh điển của AVSpeechSynthesizer).
        synth.delegate = SharedSynthDelegate.shared
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configureSession()
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = Self.vietnameseVoice()
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        lastSpoken = trimmed
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
    }

    /// Văn bản đọc cho một card HUD: "Camera phạt nguội, 165 mét".
    /// `nonisolated` — hàm thuần, test gọi từ bất kỳ thread nào.
    nonisolated static func alertText(_ alert: HazardAlert) -> String {
        let distance: String
        if alert.distanceM >= 1000 {
            distance = String(format: "%.1f ki lô mét", alert.distanceM / 1000)
        } else {
            distance = "\(Int(alert.distanceM.rounded())) mét"
        }
        if alert.title.lowercased().hasPrefix("giới hạn") {
            return "\(alert.title), sau \(distance)"
        }
        return "\(alert.title), \(distance)"
    }

    static func vietnameseVoice() -> AVSpeechSynthesisVoice? {
        if let voice = AVSpeechSynthesisVoice(language: "vi-VN") { return voice }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("vi") }
    }

    private func configureSession() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}

/// Delegate tĩnh — AVSpeechSynthesizer giữ weak reference, nên phải có đối tượng
/// sống lâu hơn synthesis (bug kinh điển: app im lặng đột ngột nếu delegate dealloc).
private final class SharedSynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SharedSynthDelegate()
}

// MARK: - Tiếng báo ngắn (không cần file âm thanh)

enum AlertSound {
    /// "Tink" system sound — attention-getter trước khi voice đọc cảnh báo.
    static func beep() {
        AudioServicesPlaySystemSound(1057)
    }
}
