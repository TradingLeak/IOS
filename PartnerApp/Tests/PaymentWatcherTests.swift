import XCTest
@testable import PartnerHub

final class PaymentWatcherTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_795_428_000) // 2026-11-23T10:00:00Z

    private func reward(_ date: String, _ usd: String) -> RewardRow {
        RewardRow(rewardDate: date,
                  rewardUsd: usd,
                  reward: nil,
                  volumeLots: 1,
                  volumeMlnUsd: nil,
                  ordersCount: 1,
                  currency: "USD",
                  clientAccount: "12345678",
                  clientAccountType: "standard",
                  clientUid: "u1",
                  country: "VN",
                  platform: "mt5",
                  linkCode: nil,
                  partnerAccount: "9001",
                  partnerAccountName: nil,
                  subpartnerAccount: nil)
    }

    private func rebate(id: Int,
                        status: String = "processed",
                        usd: Double,
                        processed: String? = "2026-11-23T09:30:00Z",
                        error: String? = nil) -> RebatePaymentRow {
        RebatePaymentRow(id: id,
                         partnerAccount: "9001",
                         status: status,
                         clientAccount: "87654321",
                         clientAccountType: "standard",
                         destinationClientAccount: nil,
                         reward: usd,
                         rewardUsd: usd,
                         volumeLots: 2,
                         rebate: usd,
                         rebateUsd: usd,
                         processedDate: processed,
                         errorCode: error)
    }

    // MARK: - Lần đầu chỉ ghi nhận baseline

    func testFirstRunOnlyRecordsBaseline() {
        let result = PaymentWatcher.diff(previous: nil,
                                         rewards: [reward("2026-11-20", "10.50"), reward("2026-11-21", "3")],
                                         rebatePayments: [rebate(id: 1, usd: 2)],
                                         now: now)

        XCTAssertTrue(result.events.isEmpty, "Lần đầu không được báo khoản cũ là khoản mới")
        XCTAssertEqual(result.snapshot.rewardDates, ["2026-11-20", "2026-11-21"])
        XCTAssertEqual(result.snapshot.rebatePaymentIDs, [1])
        XCTAssertEqual(result.snapshot.lastChecked, now)
    }

    // MARK: - Hoa hồng theo ngày

    func testNewRewardDateProducesEventWithSummedAmount() throws {
        let baseline = PaymentSnapshot(rewardDates: ["2026-11-20", "2026-11-21"],
                                       rebatePaymentIDs: [],
                                       lastChecked: now)
        let result = PaymentWatcher.diff(previous: baseline,
                                         rewards: [
                                            reward("2026-11-20", "10.50"),
                                            reward("2026-11-21", "3"),
                                            reward("2026-11-22", "5.25"),
                                            reward("2026-11-22", "1.75")
                                         ],
                                         rebatePayments: [],
                                         now: now)

        XCTAssertEqual(result.events.count, 1)
        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(event.kind, .reward)
        XCTAssertEqual(event.id, "reward:2026-11-22")
        XCTAssertEqual(event.amountUSD, Decimal(string: "7.00")!)
        XCTAssertEqual(event.amountText, Fmt.usd(Decimal(string: "7.00")!))
        XCTAssertEqual(result.snapshot.rewardDates.count, 3)
    }

    func testNoNewDataProducesNoEvents() {
        let baseline = PaymentSnapshot(rewardDates: ["2026-11-20"], rebatePaymentIDs: [1], lastChecked: now)
        let result = PaymentWatcher.diff(previous: baseline,
                                         rewards: [reward("2026-11-20", "10.50")],
                                         rebatePayments: [rebate(id: 1, usd: 2)],
                                         now: now)

        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.snapshot.rewardDates, ["2026-11-20"])
        XCTAssertEqual(result.snapshot.rebatePaymentIDs, [1])
    }

    func testAmountChangeOnKnownDateDoesNotProduceEvent() {
        let baseline = PaymentSnapshot(rewardDates: ["2026-11-20"], rebatePaymentIDs: [], lastChecked: now)
        let result = PaymentWatcher.diff(previous: baseline,
                                         rewards: [reward("2026-11-20", "99")],
                                         rebatePayments: [],
                                         now: now)

        XCTAssertTrue(result.events.isEmpty)
    }

    // MARK: - Hoàn phí (autorebate)

    func testNewRebatePaymentsProduceEventsByStatus() {
        let baseline = PaymentSnapshot(rewardDates: [], rebatePaymentIDs: [1], lastChecked: now)
        let result = PaymentWatcher.diff(previous: baseline,
                                         rewards: [],
                                         rebatePayments: [
                                            rebate(id: 1, usd: 2),
                                            rebate(id: 2, status: "processed", usd: 2.5),
                                            rebate(id: 3, status: "rejected", usd: 4, error: "NOT_ENOUGH_FUNDS")
                                         ],
                                         now: now)

        XCTAssertEqual(result.events.count, 2)
        let processed = result.events.first { $0.id == "rebate:2" }
        let rejected = result.events.first { $0.id == "rebate:3" }
        XCTAssertEqual(processed?.kind, .rebateProcessed)
        XCTAssertEqual(processed?.amountUSD, Decimal(2.5))
        XCTAssertTrue(processed?.detail.contains("••4321") ?? false)
        XCTAssertEqual(processed?.dateText, "23/11/2026")
        XCTAssertEqual(rejected?.kind, .rebateRejected)
        XCTAssertTrue(rejected?.detail.contains("NOT_ENOUGH_FUNDS") ?? false)
        XCTAssertEqual(result.snapshot.rebatePaymentIDs, [1, 2, 3])
    }

    func testUnknownRebateStatusIsRecordedButNotReported() {
        let baseline = PaymentSnapshot(rewardDates: [], rebatePaymentIDs: [], lastChecked: now)
        let result = PaymentWatcher.diff(previous: baseline,
                                         rewards: [],
                                         rebatePayments: [rebate(id: 7, status: "PENDING", usd: 1)],
                                         now: now)

        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.snapshot.rebatePaymentIDs, [7])
    }

    func testEventsSortedNewestFirst() {
        let baseline = PaymentSnapshot(rewardDates: [], rebatePaymentIDs: [], lastChecked: now)
        let result = PaymentWatcher.diff(previous: baseline,
                                         rewards: [reward("2026-11-19", "1"), reward("2026-11-21", "2")],
                                         rebatePayments: [rebate(id: 5, usd: 3, processed: "2026-11-23T08:00:00Z")],
                                         now: now)

        XCTAssertEqual(result.events.map(\.id), ["rebate:5", "reward:2026-11-21", "reward:2026-11-19"])
    }

    // MARK: - Nội dung thông báo

    func testSummarySingleAndMultiple() {
        let single = PaymentEvent(id: "reward:2026-11-22", kind: .reward,
                                  amountUSD: Decimal(string: "7.5")!, dateText: "22/11/2026",
                                  detail: "", sortDate: nil)
        let one = PaymentWatcher.summary(of: [single])
        XCTAssertEqual(one.title, "Hoa hồng mới đã trả")
        XCTAssertEqual(one.body, "$7,50 · 22/11/2026")

        let warning = PaymentEvent(id: "rebate:3", kind: .rebateRejected,
                                   amountUSD: Decimal(4), dateText: "", detail: "KH ••4321", sortDate: nil)
        let many = PaymentWatcher.summary(of: [single, warning])
        XCTAssertEqual(many.title, "2 khoản thanh toán mới")
        XCTAssertTrue(many.body.hasPrefix("Tổng $7,50 · gần nhất: "), many.body)

        XCTAssertEqual(PaymentWatcher.summary(of: []).title, "PartnerHub")
    }

    func testKindFromStatus() {
        XCTAssertEqual(PaymentWatcher.kind(forRebateStatus: "processed"), .rebateProcessed)
        XCTAssertEqual(PaymentWatcher.kind(forRebateStatus: "REJECTED"), .rebateRejected)
        XCTAssertEqual(PaymentWatcher.kind(forRebateStatus: "error"), .rebateError)
        XCTAssertNil(PaymentWatcher.kind(forRebateStatus: "PENDING"))
    }

    // MARK: - Cửa sổ thời gian truy vấn

    func testRewardQueryWindowUsesLastCheckedOrThirtyDays() throws {
        let lastChecked = try XCTUnwrap(Fmt.parseDate("2026-11-20T12:00:00Z"))

        let fromRecent = PaymentWatcher.rewardQuery(lastChecked: lastChecked, now: now)
        XCTAssertEqual(fromRecent.first { $0.0 == "reward_date_from" }?.1, "2026-11-19")
        XCTAssertEqual(fromRecent.first { $0.0 == "reward_date_to" }?.1, "2026-11-23")
        XCTAssertEqual(fromRecent.first { $0.0 == "aggregate_by" }?.1, "day")

        let fromOld = PaymentWatcher.rewardQuery(lastChecked: Fmt.parseDate("2026-10-01T00:00:00Z"), now: now)
        XCTAssertEqual(fromOld.first { $0.0 == "reward_date_from" }?.1, "2026-10-25")

        let first = PaymentWatcher.rewardQuery(lastChecked: nil, now: now)
        XCTAssertEqual(first.first { $0.0 == "reward_date_from" }?.1, "2026-10-25")
    }

    // MARK: - Snapshot lưu/đọc

    func testSnapshotCodableRoundTrip() throws {
        let snapshot = PaymentSnapshot(rewardDates: ["2026-11-20", "2026-11-21"],
                                       rebatePaymentIDs: [1, 2, 3],
                                       lastChecked: now)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PaymentSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}
