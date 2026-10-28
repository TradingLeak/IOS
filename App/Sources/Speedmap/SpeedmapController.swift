import Foundation
import CoreLocation
import Combine

// MARK: - HazardAlert

/// Một cảnh báo đang hiện trên HUD (camera / biển báo / sắp đổi giới hạn).
struct HazardAlert: Identifiable, Equatable {
    enum Kind {
        case camera
        case speedLimitChange
        case speedLimitSign
        case residentArea
        case noOvertaking
        case tollBooth
        case trafficLight
        case danger

        /// Ưu tiên khi 2 cảnh báo cùng khoảng cách.
        var priority: Int {
            switch self {
            case .camera: return 0
            case .noOvertaking: return 1
            case .speedLimitChange: return 2
            case .speedLimitSign: return 3
            case .residentArea: return 4
            case .tollBooth: return 5
            case .trafficLight: return 6
            case .danger: return 7
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let distanceM: Double
    let speedLimitKmh: Int?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: HazardAlert, rhs: HazardAlert) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && abs(lhs.distanceM - rhs.distanceM) < 0.5
            && lhs.speedLimitKmh == rhs.speedLimitKmh
    }
}

// MARK: - SpeedmapController (HUD alert engine)
//
// Nhận CLLocation 1–2 Hz → map-matching đường hiện tại (lấy giới hạn tốc độ) →
// quét camera/biển báo trong tầm D_warn (clamp v×4.5, 100…400m; biển 350m) →
// lookahead đổi giới hạn tốc độ → phát hành `alerts` cho SpeedHudOverlay.
//
// Thuật toán port từ firmware VietHUD (SpeedLimitManager.cpp), đơn giản hoá
// cho iPhone: không route-based lookahead (P1: nối NavigationSession).

@MainActor
final class SpeedmapController: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var loadError: String?
    @Published private(set) var metadata: SpeedmapMetadata?

    @Published private(set) var alerts: [HazardAlert] = []
    @Published private(set) var road: RoadMatch?
    @Published private(set) var speedLimitKmh: Int?
    @Published private(set) var speedKmh: Double?

    private(set) var database: SpeedmapDatabase?
    private var lastLocation: CLLocation?
    private var active: [HazardAlert] = []

    /// - Parameter database: truyền sẵn (test) — nếu có thì `isReady` ngay lập tức.
    init(database: SpeedmapDatabase? = nil) {
        if let database {
            install(database)
        }
    }

    func install(_ db: SpeedmapDatabase) {
        database = db
        metadata = db.metadata
        loadError = nil
        isReady = true
    }

    /// Nạp 7 file speedmap từ bundle (nền — không chặn frame đầu).
    func loadBundled(bundle: Bundle = .main) {
        guard database == nil else { return }
        Task {
            do {
                let db = try await Task.detached(priority: .userInitiated) {
                    guard let dir = SpeedmapDatabase.defaultDirectory(bundle: bundle) else {
                        throw SpeedmapError.missingFile("speedmap/*.bin trong Bundle")
                    }
                    return try SpeedmapDatabase.load(directory: dir)
                }.value
                install(db)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - Input GPS

    func update(with location: CLLocation) {
        lastLocation = location
        guard database != nil else { return }
        tick()
    }

    /// Chạy một lượt tính toán (test gọi trực tiếp sau khi `update`).
    func tick() {
        guard let db = database, let loc = lastLocation else { return }

        let coord = loc.coordinate
        let moving = loc.speed >= 0.5
        let course: Double? = (moving && loc.course >= 0 && loc.course <= 359) ? loc.course : nil
        let speed = loc.speed >= 0 ? loc.speed * 3.6 : 0
        speedKmh = loc.speed >= 0 ? speed : nil

        // ① Đường hiện tại (hysteresis giữ segment cũ)
        let match = db.matchRoad(at: coord,
                                 headingDeg: course,
                                 previousSegmentId: road?.segment.id)
        road = match
        let currentLimit = match.flatMap { $0.segment.hasSpeedLimit ? Int($0.segment.speedLimitKmh) : nil }
        speedLimitKmh = currentLimit

        let horizon = SpeedmapMath.dynamicWarnDistance(speedKmh: speed)
        let signHorizon = SpeedmapMath.signWarnDistanceM
        var candidates: [HazardAlert] = []

        // ② Camera phạt nguội / camera tốc độ
        for cam in db.cameras(near: coord, radiusM: horizon) {
            let dist = SpeedmapMath.meters(coord, cam.coordinate)
            guard dist <= horizon else { continue }
            guard isRelevant(cam.coordinate, course: course, dist: dist) else { continue }
            if !cam.isOmnidirectional, let course, dist > 45,
               SpeedmapMath.angularDiff(course, Double(cam.directionDeg)) > 100 {
                continue
            }
            let limit = cam.speedLimitKmh > 0 ? Int(cam.speedLimitKmh) : nil
            candidates.append(HazardAlert(id: "cam-\(cam.osmId)",
                                          kind: .camera,
                                          title: "Camera phạt nguội",
                                          subtitle: limit.map { "Giới hạn \($0) km/h" },
                                          distanceM: dist,
                                          speedLimitKmh: limit,
                                          coordinate: cam.coordinate))
        }

        // ③ Biển báo quy phạm (signs.bin, đã loại dòng camera trùng lặp lúc load)
        for sign in db.signs(near: coord, radiusM: signHorizon) {
            let dist = SpeedmapMath.meters(coord, sign.coordinate)
            guard dist <= signHorizon else { continue }
            guard isRelevant(sign.coordinate, course: course, dist: dist) else { continue }
            if !sign.isOmnidirectional, let course, dist > 45,
               SpeedmapMath.angularDiff(course, Double(sign.directionDeg)) > 100 {
                continue
            }
            guard let alert = Self.alert(for: sign, distanceM: dist) else { continue }
            candidates.append(alert)
        }

        // ④ Lookahead: sắp đổi giới hạn tốc độ (mẫu 6 điểm trên quỹ đạo heading)
        if let course, let limit = currentLimit {
            let step = max(horizon / 6, 25)
            var d = step
            while d <= horizon + 0.01 {
                let p = SpeedmapMath.coordinate(coord, moving: d, bearingDeg: course)
                if let ahead = db.matchRoad(at: p, headingDeg: course, searchRadiusM: 25),
                   ahead.segment.id != match?.segment.id,
                   ahead.segment.hasSpeedLimit,
                   Int(ahead.segment.speedLimitKmh) != limit {
                    candidates.append(HazardAlert(id: "spd-\(ahead.segment.id)",
                                                  kind: .speedLimitChange,
                                                  title: "Giới hạn \(ahead.segment.speedLimitKmh) km/h",
                                                  subtitle: "Sắp thay đổi giới hạn",
                                                  distanceM: d,
                                                  speedLimitKmh: Int(ahead.segment.speedLimitKmh),
                                                  coordinate: p))
                    break
                }
                d += step
            }
        }

        // ⑤ Giữ card đã hiện tới khi qua mặt hẳn (chống chớp màn hình)
        let freshIDs = Set(candidates.map(\.id))
        var kept: [HazardAlert] = []
        for old in active where !freshIDs.contains(old.id) {
            let dist = SpeedmapMath.meters(coord, old.coordinate)
            let ahead = isAhead(old.coordinate, course: course)
            if dist <= 40 || ((ahead ?? true) && dist <= max(horizon, signHorizon) + 30) {
                kept.append(old)
            }
        }

        let merged = candidates + kept
        let sorted = merged.sorted { lhs, rhs in
            if abs(lhs.distanceM - rhs.distanceM) >= 1 {
                return lhs.distanceM < rhs.distanceM
            }
            return lhs.kind.priority < rhs.kind.priority
        }
        let next = Array(sorted.prefix(3))
        active = next
        if alerts != next { alerts = next }
    }

    // MARK: - Tự kiểm tra (dùng điểm self-test trong metadata)

    /// true = match đúng roadId kỳ vọng · nil = không có điểm self-test.
    func runSelfTest() -> Bool? {
        guard let db = database,
              let coord = db.metadata.testCoordinate,
              db.metadata.testRoadId != 0 else { return nil }
        let match = db.matchRoad(at: coord,
                                 headingDeg: Double(db.metadata.testHeadingDeg),
                                 searchRadiusM: 40)
        return match?.segment.id == db.metadata.testRoadId
    }

    // MARK: - Helper

    /// Item có ở phía trước (nón 70°) hoặc đủ gần để coi là đang ngay bên cạnh.
    private func isRelevant(_ item: CLLocationCoordinate2D, course: Double?, dist: Double) -> Bool {
        guard let course, let from = lastLocation?.coordinate else { return true }
        let toItem = SpeedmapMath.bearing(from: from, to: item)
        return SpeedmapMath.angularDiff(course, toItem) <= 70 || dist <= 45
    }

    private func isAhead(_ item: CLLocationCoordinate2D, course: Double?) -> Bool? {
        guard let course, let from = lastLocation?.coordinate else { return nil }
        let toItem = SpeedmapMath.bearing(from: from, to: item)
        return SpeedmapMath.angularDiff(course, toItem) <= 90
    }

    /// TrafficSign → HazardAlert (nil nếu không phải loại hiển thị được).
    static func alert(for sign: TrafficSign, distanceM: Double) -> HazardAlert? {
        let end = sign.isEndOfRestriction
        let kind: HazardAlert.Kind
        let title: String
        switch sign.type {
        case .speedLimit:
            if end {
                kind = .speedLimitSign
                title = "Hết giới hạn tốc độ"
            } else {
                guard sign.speedLimitKmh > 0 else { return nil }
                kind = .speedLimitSign
                title = "Giới hạn \(sign.speedLimitKmh) km/h"
            }
        case .residentArea:
            kind = .residentArea
            title = end ? "Hết khu dân cư" : "Khu dân cư"
        case .noOvertaking:
            kind = .noOvertaking
            title = end ? "Hết cấm vượt" : "Cấm vượt"
        case .tollBooth:
            kind = .tollBooth
            title = end ? "Đã qua trạm thu phí" : "Trạm thu phí"
        case .trafficLight:
            guard !end else { return nil }
            kind = .trafficLight
            title = "Đèn giao thông"
        case .dangerOther:
            kind = .danger
            title = "Đoạn đường nguy hiểm"
        case .camera, .unknown:
            return nil   // camera đã có ở cameras.bin
        }
        return HazardAlert(id: "sgn-\(sign.id)",
                           kind: kind,
                           title: title,
                           subtitle: nil,
                           distanceM: distanceM,
                           speedLimitKmh: nil,
                           coordinate: sign.coordinate)
    }
}
