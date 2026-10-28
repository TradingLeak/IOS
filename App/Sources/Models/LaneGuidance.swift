import Foundation

/// Gợi ý làn đường khi sắp tới chỗ rẽ.
///
/// Apple Maps (MapKit) **không** trả về dữ liệu làn. Cấu trúc này suy ra làn cần đi từ
/// câu chỉ dẫn của bước hiện tại theo quy tắc giao thông Việt Nam:
///
/// - rẽ trái / quay đầu → làn trái nhất
/// - rẽ phải / lối ra / vòng xuyến → làn phải nhất
/// - đi thẳng, tới nơi → không gợi ý (tránh làm rối màn hình)
///
/// Không gọi dịch vụ ngoài, không cần API key. Khi nào bộ dữ liệu OSM có `turn:lanes`
/// thì chỉ cần thay `hint(for:distance:)` bằng dữ liệu thật, phần giao diện giữ nguyên.
struct LaneGuidance: Equatable {
    /// Số làn vẽ trên dải gợi ý (2…4).
    let laneCount: Int
    /// Chỉ số làn được tô sáng (0 = trái nhất).
    let highlighted: Set<Int>
    /// Nhãn ngắn: “Làn trái”, “Làn phải”…
    let caption: String

    init(laneCount: Int, highlighted: Set<Int>, caption: String) {
        self.laneCount = max(2, min(4, laneCount))
        self.highlighted = highlighted.filter { $0 >= 0 && $0 < max(2, min(4, laneCount)) }
        self.caption = caption
    }

    /// `nil` khi không cần hiện dải làn (đi thẳng, đã tới nơi, còn quá xa).
    static func hint(for step: RouteStep?, distance: Double) -> LaneGuidance? {
        guard let step, distance.isFinite, distance > 0, distance <= 400 else { return nil }
        let text = step.instruction.lowercased()

        if text.contains("đến nơi") || text.contains("điểm đến") || text.contains("arrive") {
            return nil
        }
        if text.contains("vòng xuyến") || text.contains("roundabout") {
            return LaneGuidance(laneCount: 3, highlighted: [2], caption: "Vào vòng xuyến")
        }
        if text.contains("quay đầu") || text.contains("u-turn") || text.contains("uturn") {
            return LaneGuidance(laneCount: 3, highlighted: [0], caption: "Làn trái")
        }
        if text.contains("rẽ trái") || text.contains("quẹo trái") || text.contains("turn left") {
            return LaneGuidance(laneCount: 3, highlighted: [0], caption: "Làn trái")
        }
        if text.contains("rẽ phải") || text.contains("quẹo phải") || text.contains("turn right") {
            return LaneGuidance(laneCount: 3, highlighted: [2], caption: "Làn phải")
        }
        if text.contains("lối ra") || text.contains("tách làn") || text.contains("exit")
            || text.contains("nhập làn") || text.contains("merge") {
            return LaneGuidance(laneCount: 3, highlighted: [2], caption: "Làn phải")
        }
        return nil
    }

    /// Hướng mũi tên vẽ trên từng làn (chỉ để hiển thị).
    func symbol(forLane index: Int) -> String {
        guard highlighted.contains(index) else { return "arrow.up" }
        if index == 0 { return "arrow.turn.up.left" }
        if index >= laneCount - 1 { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}
