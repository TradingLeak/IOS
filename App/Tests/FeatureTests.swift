import XCTest
import MapKit
@testable import VietMap

// MARK: - Tìm kiếm không dấu / xếp hạng

final class SearchRankingTests: XCTestCase {

    private func place(_ name: String, _ subtitle: String = "", lat: Double = 21.03, lng: Double = 105.85) -> Place {
        Place(name: name, subtitle: subtitle, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }

    func testNormalizeRemovesVietnameseDiacritics() {
        XCTAssertEqual(SearchRanking.normalize("Hồ Hoàn Kiếm"), "ho hoan kiem")
        XCTAssertEqual(SearchRanking.normalize("Đường Nguyễn Trãi"), "duong nguyen trai")
        XCTAssertEqual(SearchRanking.normalize("  Phố   Cổ  "), "pho co")
        XCTAssertEqual(SearchRanking.normalize("Quận 1, TP.HCM"), "quan 1 tp hcm")
    }

    func testUnaccentedQueryMatchesAccentedName() {
        let lake = place("Hồ Tây")
        XCTAssertTrue(SearchRanking.matches(lake, query: "ho tay"))
        XCTAssertTrue(SearchRanking.matches(lake, query: "HỒ TÂY"))
        XCTAssertFalse(SearchRanking.matches(lake, query: "ho guom"))
    }

    func testMatchesSubtitleToo() {
        let cafe = place("The Coffee House", "Nguyễn Trãi, Thanh Xuân")
        XCTAssertTrue(SearchRanking.matches(cafe, query: "thanh xuan"))
    }

    func testFilterKeepsOrderForEmptyQuery() {
        let items = [place("A"), place("B")]
        XCTAssertEqual(SearchRanking.filter(items, query: "   ").count, 2)
        XCTAssertEqual(SearchRanking.filter(items, query: "a").count, 1)
    }

    func testRankPrefersPrefixThenDistance() {
        let nearButContains = place("Quán Hồ Tây", lat: 21.0300, lng: 105.8500)
        let farButPrefix = place("Hồ Tây", lat: 21.0700, lng: 105.8200)
        let origin = CLLocationCoordinate2D(latitude: 21.0300, longitude: 105.8500)
        let ranked = SearchRanking.rank([nearButContains, farButPrefix], query: "ho tay", near: origin)
        XCTAssertEqual(ranked.first?.name, "Hồ Tây", "Khớp đầu tên phải đứng trước khớp giữa tên")
    }

    func testRankWithoutLocationKeepsStableOrdering() {
        let a = place("Hồ Tây")
        let b = place("Hồ Tây 2")
        let ranked = SearchRanking.rank([b, a], query: "ho tay", near: nil)
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.first?.name, "Hồ Tây")
    }

    func testDistanceText() {
        let target = place("Điểm", lat: 21.0400, lng: 105.8500)
        let origin = CLLocationCoordinate2D(latitude: 21.0300, longitude: 105.8500)
        let text = SearchRanking.distanceText(target, from: origin)
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.hasPrefix("cách ") ?? false)
        XCTAssertNil(SearchRanking.distanceText(target, from: nil))
    }
}

// MARK: - Chia sẻ tuyến

final class RouteShareTests: XCTestCase {

    private func place(_ name: String, lat: Double, lng: Double) -> Place {
        Place(name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }

    private var route: RouteOption {
        let coordinates = [CLLocationCoordinate2D(latitude: 21.03, longitude: 105.85),
                           CLLocationCoordinate2D(latitude: 21.05, longitude: 105.83)]
        return RouteOption(name: "Tuyến chính",
                           distance: 5200,
                           expectedTravelTime: 900,
                           coordinates: coordinates,
                           steps: [],
                           mode: .motorcycle,
                           advisoryNotices: [])
    }

    private func query(_ url: URL?) -> [String: String] {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            values[item.name] = item.value
        }
        return values
    }

    func testAppleMapsURLCarriesCoordinates() {
        let url = RouteShare.appleMapsURL(origin: place("A", lat: 21.03, lng: 105.85),
                                          destination: place("B", lat: 21.05, lng: 105.83),
                                          mode: .motorcycle)
        XCTAssertEqual(url?.host, "maps.apple.com")
        let items = query(url)
        XCTAssertEqual(items["saddr"], "21.030000,105.850000")
        XCTAssertEqual(items["daddr"], "21.050000,105.830000")
        XCTAssertEqual(items["dirflg"], "d")
    }

    func testWalkingUsesWalkingFlag() {
        let url = RouteShare.appleMapsURL(origin: nil,
                                          destination: place("B", lat: 21.05, lng: 105.83),
                                          mode: .walking)
        let items = query(url)
        XCTAssertEqual(items["dirflg"], "w")
        XCTAssertNil(items["saddr"])
    }

    func testWaypointsAreChained() {
        let url = RouteShare.appleMapsURL(origin: place("A", lat: 21.03, lng: 105.85),
                                          destination: place("C", lat: 21.06, lng: 105.80),
                                          waypoints: [place("B", lat: 21.05, lng: 105.83)],
                                          mode: .motorcycle)
        let destination = query(url)["daddr"] ?? ""
        XCTAssertTrue(destination.contains("+to:"))
    }

    func testMessageHasRouteFacts() {
        let message = RouteShare.message(origin: place("Cầu Giấy", lat: 21.03, lng: 105.80),
                                         destination: place("Hồ Hoàn Kiếm", lat: 21.028, lng: 105.852),
                                         waypoints: [place("Hồ Tây", lat: 21.06, lng: 105.82)],
                                         route: route,
                                         alerts: 4,
                                         mode: .motorcycle)
        XCTAssertTrue(message.contains("Cầu Giấy → Hồ Hoàn Kiếm"))
        XCTAssertTrue(message.contains("Ghé: Hồ Tây"))
        XCTAssertTrue(message.contains("4 cảnh báo"))
        XCTAssertTrue(message.contains("maps.apple.com"))
    }
}

// MARK: - Báo cáo sự cố

final class IncidentTests: XCTestCase {

    func testLifetimeDiffersByKind() {
        XCTAssertLessThan(IncidentKind.trafficJam.lifetime, IncidentKind.pothole.lifetime)
        XCTAssertEqual(IncidentKind.police.lifetime, 45 * 60)
        XCTAssertEqual(IncidentKind.pothole.lifetimeText, "7 ngày")
    }

    func testExpiry() {
        let fresh = IncidentReport(kind: .police,
                                   coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105))
        XCTAssertFalse(fresh.isExpired)

        let old = IncidentReport(kind: .police,
                                 coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105),
                                 createdAt: Date().addingTimeInterval(-60 * 60))
        XCTAssertTrue(old.isExpired)
        XCTAssertEqual(old.remainingText, "đã hết hạn")
    }

    func testTitleUsesNoteWhenPresent() {
        let report = IncidentReport(kind: .flooding,
                                    coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105),
                                    note: "  ngập 30 cm  ")
        XCTAssertEqual(report.title, "ngập 30 cm")
        XCTAssertTrue(report.subtitle.contains("Ngập"))
    }

    func testDistanceFromCoordinate() {
        let report = IncidentReport(kind: .accident,
                                    coordinate: CLLocationCoordinate2D(latitude: 21.0300, longitude: 105.8500))
        let meters = report.distance(from: CLLocationCoordinate2D(latitude: 21.0400, longitude: 105.8500))
        XCTAssertEqual(meters, 1111, accuracy: 60)
    }

    func testSeverityIsHigherWhenFresh() {
        let fresh = IncidentReport(kind: .accident,
                                   coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105))
        XCTAssertEqual(fresh.severityHint, 2)

        let older = IncidentReport(kind: .accident,
                                   coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105),
                                   createdAt: Date().addingTimeInterval(-30 * 60))
        XCTAssertEqual(older.severityHint, 1)
    }

    func testSpeakingWarningIsVietnamese() {
        for kind in IncidentKind.allCases {
            XCTAssertFalse(kind.spokenWarning.isEmpty)
            XCTAssertTrue(kind.spokenWarning.hasPrefix("Chú ý"))
        }
    }
}
