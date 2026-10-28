import Foundation
import AVFoundation
import CoreLocation

/// Đọc cảnh báo bằng giọng tiếng Việt của iOS (chạy offline, không cần mạng).
@MainActor
final class VoiceAlertService {

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpoken: [String: Date] = [:]
    private var lastSpeechAt: Date?

    var isEnabled = true
    /// Khoảng cách tối thiểu giữa hai lần đọc cùng một cảnh báo.
    var cooldown: TimeInterval = 30

    func announce(_ text: String, key: String, cooldown: TimeInterval? = nil) {
        guard isEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        let wait = cooldown ?? self.cooldown

        if let last = lastSpoken[key], now.timeIntervalSince(last) < wait { return }
        if let last = lastSpeechAt, now.timeIntervalSince(last) < 2.5 { return }

        lastSpoken[key] = now
        lastSpeechAt = now

        configureAudioSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1

        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Xoá bộ nhớ đệm "đã đọc" — dùng khi bắt đầu tuyến mới.
    func reset() {
        lastSpoken.removeAll()
        lastSpeechAt = nil
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }
}
