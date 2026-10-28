import Foundation

/// Nhận xét tuyến **soạn sẵn, chạy offline** — không gọi mạng, không cần API key.
///
/// Mọi câu chữ ở đây suy ra trực tiếp từ số liệu thật của tuyến (thời gian, quãng đường,
/// số camera, cao tốc, phí cầu đường) nên luôn khớp với những gì người dùng đang thấy
/// và hiện ra ngay, không phải chờ máy chủ.
enum RouteInsight {

    // MARK: - Tóm tắt một tuyến

    static func summary(route: RouteOption,
                        originName: String,
                        destinationName: String,
                        alerts: [ActiveAlert] = []) -> String {
        var text = "Tuyến \(route.mode.title.lowercased()) từ \(originName) đến \(destinationName) "
            + "dài \(route.formattedDistance), dự kiến \(route.formattedDuration)"
        if let arrival = Format.arrival(after: route.expectedTravelTime) {
            text += " (tới nơi khoảng \(arrival))"
        }
        text += "."

        if route.steps.count <= 3 {
            text += " Đường khá đơn giản, chỉ \(route.steps.count) bước rẽ."
        } else {
            text += " Có \(route.steps.count) bước rẽ, nên bám theo danh sách chỉ dẫn bên dưới."
        }

        let cameras = alerts.filter { $0.alert.kind.isCamera }.count
        let limits = alerts.filter { $0.alert.kind.carriesSpeedLimit }.count
        if cameras > 0 || limits > 0 {
            var parts: [String] = []
            if cameras > 0 { parts.append("\(cameras) camera") }
            if limits > 0 { parts.append("\(limits) biển/vùng giới hạn tốc độ") }
            text += " Trên đường có " + parts.joined(separator: " và ") + " — app sẽ báo trước."
        }

        if let toll = route.tollCostText {
            text += " Phí cầu đường khoảng \(toll)."
        }

        if !route.advisoryNotices.isEmpty {
            text += " Lưu ý: \(route.advisoryNotices.joined(separator: "; "))."
        }
        return text
    }

    // MARK: - Đề xuất chọn tuyến

    /// So sánh các phương án và nói rõ vì sao nên chọn phương án đầu bảng.
    static func advice(routes: [RouteOption], scores: [RouteScore]) -> String? {
        guard let best = scores.first,
              let route = routes.first(where: { $0.id == best.routeID }) else { return nil }

        var text = "Nên đi \(route.name): \(route.formattedDuration), \(route.formattedDistance)"
        if let second = scores.dropFirst().first {
            let gap = Int((best.total - second.total).rounded())
            if gap > 0 {
                text += " — điểm \(Int(best.total.rounded())) so với \(Int(second.total.rounded())) của phương án sau"
            }
        }
        text += "."
        if !best.summary.isEmpty {
            text += " " + best.summary
            if !best.summary.hasSuffix(".") { text += "." }
        }
        if let toll = route.tollCostText {
            text += " Phí cầu đường khoảng \(toll)."
        }
        return text
    }

    /// Nhãn ngắn trên thẻ tuyến ngoài bản đồ.
    static func compactAdvice(route: RouteOption, score: RouteScore?) -> String? {
        guard let score else { return nil }
        var parts: [String] = [score.badge]
        if score.cameraCount > 0 { parts.append("\(score.cameraCount) camera") }
        if score.expresswayShare > 0.05 { parts.append("có cao tốc") }
        if let toll = route.tollCostText { parts.append(toll) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Câu nhắc khi đang dẫn đường

    /// Nhắc trước ngã rẽ theo khoảng cách còn lại (kiểu ứng dụng thương mại).
    static func turnAnnouncement(step: RouteStep, distance: Double) -> String {
        let instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return "Tiếp tục di chuyển." }
        if distance <= 45 || instruction.lowercased().hasPrefix("đến nơi") {
            return instruction.hasSuffix(".") ? instruction : instruction + "."
        }
        let gap = Format.hudDistance(max(0, distance))
        let lowered = instruction.prefix(1).lowercased() + String(instruction.dropFirst())
        return "Sau \(gap), \(lowered)."
    }

    /// Câu đọc khi vừa qua một bước: giới thiệu bước kế tiếp.
    static func nextStepAnnouncement(step: RouteStep) -> String {
        let instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return "" }
        return instruction.hasSuffix(".") ? instruction : instruction + "."
    }
}
