import XCTest
@testable import PartnerHub

final class ModelTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return jsonDecoder
    }

    func testRewardReportDecodes() throws {
        let json = """
        {
          "data": [
            {
              "client_account": "12345678",
              "client_account_type": "standard",
              "client_uid": null,
              "country": "VN",
              "platform": "mt5",
              "currency": "USD",
              "link_code": "demo22",
              "orders_count": 2,
              "partner_account": "9001",
              "partner_account_name": "Main",
              "reward": "12.50",
              "reward_date": "2026-07-30T10:30:00Z",
              "reward_usd": "12.50",
              "subpartner_account": null,
              "volume_lots": 3.25,
              "volume_mln_usd": 0.31
            }
          ],
          "totals": {
            "count": 1,
            "volume_mln_usd": 0.31,
            "volume_lots": 3.25,
            "reward": "12.50",
            "reward_usd": "12.50",
            "orders_count": 2,
            "currency": ["USD"]
          }
        }
        """

        let report = try decoder().decode(RewardReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.data.count, 1)
        XCTAssertEqual(report.data[0].clientAccount, "12345678")
        XCTAssertEqual(report.data[0].rewardUsdDecimal, Decimal(string: "12.50")!)
        XCTAssertEqual(report.totals.ordersCount, 2)
        XCTAssertEqual(report.totals.volumeLots, 3.25)
    }

    func testClientReportDecodes() throws {
        let json = """
        {
          "data": [
            {
              "partner_account": "9001",
              "client_uid": "8f2c1a9b7d3e4f50",
              "reg_date": "2026-07-30",
              "client_country": "VN",
              "volume_lots": 12.5,
              "volume_mln_usd": 1.2,
              "reward_usd": "45.20",
              "trade_fn": "2026-07-29",
              "client_contact_sharing_status": "shared",
              "client_status": "active",
              "last_partner_contact_sharing_dt": null,
              "comment": null,
              "rebate_amount_usd": 9.04,
              "kyc_passed": true,
              "ftd_received": true,
              "ftt_made": true,
              "last_client_contact_sharing_dt": null,
              "client_balance": 2,
              "client_equity": 2,
              "deposit_amount": 2,
              "ftd_amount": 1,
              "last_week_failed_deposit_count": 0
            }
          ],
          "totals": {
            "count": 1,
            "volume_lots": 12.5,
            "volume_mln_usd": 1.2,
            "reward_usd": "45.20",
            "server_dt": "2026-07-30T10:30:00Z",
            "available_for_request": 0
          }
        }
        """

        let report = try decoder().decode(ClientReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.data.count, 1)
        XCTAssertEqual(report.data[0].clientCountry, "VN")
        XCTAssertTrue(report.data[0].kycPassed == true)
        XCTAssertEqual(report.data[0].rewardUsdDecimal, Decimal(string: "45.20")!)
        XCTAssertEqual(report.totals.count, 1)
    }

    func testTierStateDecodes() throws {
        let json = """
        {
          "clients_count": 12,
          "usd_volume": 123456.7,
          "subpartners_count": 2,
          "subpartners_usd_volume": 5000,
          "registered_dt": "2026-07-30T10:30:00Z",
          "tier_id": 1,
          "tier_name": "Bronze",
          "tier_group": "Default",
          "tier_order": 1,
          "grace_period_start_dt": null,
          "grace_period_finish_dt": null,
          "is_second_lvl": true,
          "ib_candidate": {
            "kyc_passed": true,
            "clients": true,
            "ready_for_promotion": true,
            "promoted": false
          },
          "commission": {"pro": [17, 18], "standard": [10, null]},
          "is_ib": true,
          "qualification_tier": {"id": 2, "name": "Silver", "group": "Default", "order": 2},
          "last_grace_period_status": "APPROVED"
        }
        """

        let tier = try decoder().decode(TierState.self, from: Data(json.utf8))
        XCTAssertEqual(tier.tierName, "Bronze")
        XCTAssertEqual(tier.clientsCount, 12)
        XCTAssertEqual(tier.usdVolume, 123_456.7, accuracy: 0.001)
        XCTAssertEqual(tier.qualificationTier?.name, "Silver")
        let pro = tier.commission?["pro"]
        XCTAssertEqual(pro?.count, 2)
        XCTAssertEqual(pro?[0], 17)
        XCTAssertEqual(pro?[1], 18)
        let standard = tier.commission?["standard"]
        XCTAssertEqual(standard?[0], 10)
        XCTAssertNil(standard?[1])
    }

    func testRebateHistoryDecodes() throws {
        let json = """
        {
          "data": [
            {
              "id": 1,
              "partner_account": "9001",
              "client_account": "123",
              "client_account_type": "standard",
              "rebate_group_title": "VIP",
              "volume_lots": 1.5,
              "reward": 10,
              "reward_usd": 10,
              "rebate": 2,
              "rebate_usd": 2,
              "rebate_percent": 20,
              "status": "PROCESSED",
              "error_code": null,
              "destination_client_account": null,
              "processed_date": "2026-07-30",
              "reward_date": "2026-07-30",
              "group_id": 1
            }
          ],
          "totals": {
            "id": 1,
            "date": null,
            "clients_count": 1,
            "clients_approved_count": 1,
            "clients_rejected_count": 0,
            "reward_usd": 10,
            "topay_rebate_usd": 2,
            "status": "PROCESSED",
            "rejected_rebate_usd": 0,
            "error_rebate_usd": 0,
            "processed_rebate_usd": 2,
            "group_id": 1,
            "group_name": "VIP",
            "clients_pending_count": 0,
            "pending_reward_usd": 0
          }
        }
        """

        let report = try decoder().decode(RebateHistoryReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.data.count, 1)
        XCTAssertEqual(report.data[0].status, "PROCESSED")
        XCTAssertEqual(report.data[0].rebateUsd, 2)
        XCTAssertEqual(report.totals.processedRebateUsd, 2)
    }

    func testDefaultLinkDecodes() throws {
        let json = """
        {
          "full_default_link": "https://www.exness.com/a/demo22",
          "domain": "www.exness.com",
          "code": "demo22",
          "path": "/a/demo22",
          "url": "https://www.exness.com/a/demo22"
        }
        """
        let link = try decoder().decode(DefaultLink.self, from: Data(json.utf8))
        XCTAssertEqual(link.code, "demo22")
        XCTAssertEqual(link.fullDefaultLink, "https://www.exness.com/a/demo22")
    }
}
