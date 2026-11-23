import XCTest
@testable import PulseHub

final class PulseModelTests: XCTestCase {

    // MARK: - Mã hiệu

    func testSymbolCategoryDetection() {
        XCTAssertEqual(PulseSymbol.category(for: "XAUUSD"), .metals)
        XCTAssertEqual(PulseSymbol.category(for: "XAGUSD"), .metals)
        XCTAssertEqual(PulseSymbol.category(for: "BTCUSD"), .crypto)
        XCTAssertEqual(PulseSymbol.category(for: "ETHUSDm"), .crypto)
        XCTAssertEqual(PulseSymbol.category(for: "EURUSD"), .forex)
        XCTAssertEqual(PulseSymbol.category(for: "USDJPY"), .forex)
        XCTAssertEqual(PulseSymbol.category(for: "USOIL"), .energy)
        XCTAssertEqual(PulseSymbol.category(for: "NGAS"), .energy)
        XCTAssertEqual(PulseSymbol.category(for: "XYZ123"), .other)
    }

    func testDisplayNameSplitsPairs() {
        XCTAssertEqual(PulseSymbol.displayName("XAUUSD"), "XAU/USD")
        XCTAssertEqual(PulseSymbol.displayName("EURUSD"), "EUR/USD")
        XCTAssertEqual(PulseSymbol.displayName("btcusd"), "BTC/USD")
        XCTAssertEqual(PulseSymbol.displayName("USOIL"), "USOIL")
    }

    func testDigitsPerSymbol() {
        XCTAssertEqual(PulseSymbol.digits(for: "XAUUSD"), 2)
        XCTAssertEqual(PulseSymbol.digits(for: "USDJPY"), 3)
        XCTAssertEqual(PulseSymbol.digits(for: "EURUSD"), 5)
        XCTAssertEqual(PulseSymbol.digits(for: "BTCUSD"), 2)
        XCTAssertEqual(PulseSymbol.digits(for: "NGAS"), 3)
    }

    func testTimeframeSeconds() {
        XCTAssertEqual(Timeframe.M1.seconds, 60)
        XCTAssertEqual(Timeframe.H4.seconds, 14_400)
        XCTAssertEqual(Timeframe.D1.seconds, 86_400)
        XCTAssertEqual(Timeframe.allCases.count, 7)
    }

    // MARK: - Định dạng

    func testPriceFormattingUsesDotAndFixedDigits() {
        XCTAssertEqual(PulseFormat.price(4050.5, digits: 2), "4050.50")
        XCTAssertEqual(PulseFormat.price(1.1, digits: 5), "1.10000")
        XCTAssertEqual(PulseFormat.signedPrice(2, digits: 2), "+2.00")
        XCTAssertEqual(PulseFormat.signedPrice(-1.2345, digits: 2), "-1.23")
    }

    func testRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_795_428_000)
        XCTAssertEqual(PulseFormat.relativeTime(now.addingTimeInterval(-30), now: now), "vừa xong")
        XCTAssertEqual(PulseFormat.relativeTime(now.addingTimeInterval(-90), now: now), "1 phút trước")
        XCTAssertEqual(PulseFormat.relativeTime(now.addingTimeInterval(-7_200), now: now), "2 giờ trước")
        XCTAssertEqual(PulseFormat.relativeTime(now.addingTimeInterval(-86_400), now: now), "Hôm qua")
        XCTAssertEqual(PulseFormat.relativeTime(now.addingTimeInterval(300), now: now), "còn 5 phút")
        XCTAssertEqual(PulseFormat.relativeTime(now.addingTimeInterval(7_200), now: now), "còn 2 giờ")
        XCTAssertEqual(PulseFormat.relativeTime(nil), "")
    }

    func testCountdown() {
        let now = Date(timeIntervalSince1970: 1_795_428_000)
        XCTAssertEqual(PulseFormat.countdown(to: now.addingTimeInterval(2 * 3_600 + 15 * 60), now: now), "2g 15p")
        XCTAssertEqual(PulseFormat.countdown(to: now.addingTimeInterval(90_000 + 3 * 3_600), now: now), "1 ngày 4g")
        XCTAssertEqual(PulseFormat.countdown(to: now.addingTimeInterval(45), now: now), "1p")
        XCTAssertEqual(PulseFormat.countdown(to: now.addingTimeInterval(-10), now: now), "đang diễn ra")
    }

    func testDayTitleMarksTodayAndTomorrow() {
        let now = Date(timeIntervalSince1970: 1_795_428_000)
        XCTAssertTrue(PulseFormat.dayTitle(now, now: now).contains("Hôm nay"))
        XCTAssertTrue(PulseFormat.dayTitle(now.addingTimeInterval(86_400), now: now).contains("Ngày mai"))
        XCTAssertFalse(PulseFormat.dayTitle(now.addingTimeInterval(5 * 86_400), now: now).contains("Hôm nay"))
    }

    // MARK: - Lịch kinh tế

    func testCalendarJSONIsParsedWithOffset() throws {
        let json = """
        [
          {"title":"Flash Manufacturing PMI","country":"USD","date":"2026-11-23T14:45:00-05:00",
           "impact":"High","forecast":"49.8","previous":"49.2"},
          {"title":"CPI y/y","country":"AUD","date":"2026-11-24T19:30:00-05:00",
           "impact":"High","forecast":null,"previous":"3.8%"},
          {"title":"Bank Holiday","country":"JPY","date":"2026-11-23T00:00:00-05:00",
           "impact":"Holiday","forecast":"","previous":""}
        ]
        """
        let events = try EconomicCalendarService.parse(Data(json.utf8))
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].country, "USD")
        XCTAssertEqual(events[0].impact, .high)
        XCTAssertEqual(events[0].forecast, "49.8")
        XCTAssertEqual(events[1].forecast, "")
        XCTAssertEqual(events[2].impact, .holiday)
        XCTAssertEqual(events[0].flag, "🇺🇸")

        // 14:45 -05:00 = 19:45 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.hour, from: events[0].date), 19)
        XCTAssertTrue(events[0].date < events[1].date)
    }

    func testCalendarGroupingByLocalDay() throws {
        let json = """
        [
          {"title":"A","country":"USD","date":"2026-11-23T10:00:00Z","impact":"Low"},
          {"title":"B","country":"EUR","date":"2026-11-23T12:00:00Z","impact":"Medium"},
          {"title":"C","country":"GBP","date":"2026-11-25T12:00:00Z","impact":"High"}
        ]
        """
        let events = try EconomicCalendarService.parse(Data(json.utf8))
        let days = EconomicCalendarService.groupByDay(events)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].events.map(\.title), ["A", "B"])
        XCTAssertEqual(days[1].events.map(\.title), ["C"])
    }

    func testImpactFilter() {
        XCTAssertTrue(ImpactFilter.highOnly.includes(.high))
        XCTAssertFalse(ImpactFilter.highOnly.includes(.medium))
        XCTAssertTrue(ImpactFilter.mediumAndHigh.includes(.medium))
        XCTAssertFalse(ImpactFilter.mediumAndHigh.includes(.low))
        XCTAssertTrue(ImpactFilter.all.includes(.holiday))
    }

    func testEventAlertDate() {
        let event = EconomicEvent(id: "x", title: "T", country: "USD",
                                  date: Date(timeIntervalSince1970: 1_000_000),
                                  impact: .high, forecast: "", previous: "")
        XCTAssertEqual(event.alertDate(minutesBefore: 15).timeIntervalSince1970, 1_000_000 - 900)
    }

    // MARK: - RSS / Atom

    func testRSS20IsParsed() {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>FXStreet News</title>
            <item>
              <title>Gold jumps as &amp; yields fall</title>
              <link>https://www.fxstreet.com/news/gold-jumps</link>
              <description><![CDATA[<p>Gold rose <b>2.3%</b> on Monday.&nbsp;</p>]]></description>
              <pubDate>Mon, 23 Nov 2026 10:00:00 GMT</pubDate>
            </item>
            <item>
              <title>EUR/USD consolidates</title>
              <link>https://www.fxstreet.com/news/eurusd</link>
              <description>Plain description</description>
              <pubDate>Mon, 23 Nov 2026 09:30:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """
        let items = RSSParser.parse(Data(rss.utf8), category: .forex, sourceHint: "Hint")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Gold jumps as & yields fall")
        XCTAssertEqual(items[0].link, "https://www.fxstreet.com/news/gold-jumps")
        XCTAssertEqual(items[0].summary, "Gold rose 2.3% on Monday.")
        XCTAssertEqual(items[0].source, "FXStreet News")
        XCTAssertEqual(items[0].category, .forex)
        XCTAssertNotNil(items[0].date)
    }

    func testAtomFeedWithHrefAndUpdatedIsParsed() {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Federal Reserve</title>
          <entry>
            <title>FOMC statement</title>
            <link rel="alternate" href="https://www.federalreserve.gov/newsevents/pressreleases/monetary20261123a.htm"/>
            <updated>2026-11-23T19:00:00Z</updated>
            <summary>The Federal Reserve decided today…</summary>
          </entry>
        </feed>
        """
        let items = RSSParser.parse(Data(atom.utf8), category: .centralBank, sourceHint: "Fed")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "FOMC statement")
        XCTAssertEqual(items[0].link, "https://www.federalreserve.gov/newsevents/pressreleases/monetary20261123a.htm")
        XCTAssertNotNil(items[0].date)
        XCTAssertEqual(items[0].source, "Federal Reserve")
    }

    func testFeedDateFormats() {
        XCTAssertNotNil(FeedDate.parse("2026-11-23T10:00:00Z"))
        XCTAssertNotNil(FeedDate.parse("2026-11-23T10:00:00.123Z"))
        XCTAssertNotNil(FeedDate.parse("Mon, 23 Nov 2026 10:00:00 GMT"))
        XCTAssertNotNil(FeedDate.parse("Mon, 23 Nov 2026 10:00:00 +0700"))
        XCTAssertNil(FeedDate.parse("not a date"))
        XCTAssertNil(FeedDate.parse(""))
    }

    func testHTMLTextStripsTagsAndEntities() {
        XCTAssertEqual(HTMLText.plain("<p>Hello&nbsp;<b>world</b> &amp; friends</p>"), "Hello world & friends")
        let long = String(repeating: "a", count: 300)
        XCTAssertTrue(HTMLText.summary(long).hasSuffix("…"))
        XCTAssertEqual(HTMLText.summary(long).count, 241)
    }

    func testNewsMergeDedupesAndSorts() {
        let older = NewsItem(title: "Old", link: "a", summary: "", date: Date(timeIntervalSince1970: 100),
                             source: "A", category: .forex)
        let newer = NewsItem(title: "New", link: "b", summary: "", date: Date(timeIntervalSince1970: 200),
                             source: "B", category: .forex)
        let duplicate = NewsItem(title: "Old again", link: "a", summary: "", date: nil,
                                 source: "C", category: .forex)
        let merged = NewsService.merge([older, newer, duplicate])
        XCTAssertEqual(merged.map(\.title), ["New", "Old"])
        XCTAssertEqual(NewsService.search(merged, query: "new").map(\.title), ["New"])
        XCTAssertEqual(NewsService.search(merged, query: "   ").count, 2)
    }

    // MARK: - Cảnh báo giá

    func testPriceAlertAboveFiresOnceThenDisables() throws {
        let alert = PriceAlert(symbol: "XAUUSD", condition: .price, direction: .above,
                               targetValue: 4_000, basePrice: 3_900)
        XCTAssertNil(AlertEvaluator.fire(alert, price: 3_999.99))
        let fired = try XCTUnwrap(AlertEvaluator.fire(alert, price: 4_001))
        XCTAssertEqual(fired.triggerCount, 1)
        XCTAssertFalse(fired.enabled)
        XCTAssertNotNil(fired.lastTriggeredAt)
        XCTAssertNil(AlertEvaluator.fire(fired, price: 4_100), "Đã tắt thì không kích hoạt lại")
    }

    func testPriceAlertDirections() {
        let below = PriceAlert(symbol: "EURUSD", condition: .price, direction: .below,
                               targetValue: 1.05, basePrice: 1.08)
        XCTAssertNil(AlertEvaluator.fire(below, price: 1.06))
        XCTAssertNotNil(AlertEvaluator.fire(below, price: 1.05))

        let crossUp = PriceAlert(symbol: "XAUUSD", condition: .price, direction: .cross,
                                 targetValue: 4_000, basePrice: 3_900)
        XCTAssertNil(AlertEvaluator.fire(crossUp, price: 3_950))
        XCTAssertNotNil(AlertEvaluator.fire(crossUp, price: 4_000))

        let crossDown = PriceAlert(symbol: "XAUUSD", condition: .price, direction: .cross,
                                   targetValue: 3_800, basePrice: 3_900)
        XCTAssertNil(AlertEvaluator.fire(crossDown, price: 3_850))
        XCTAssertNotNil(AlertEvaluator.fire(crossDown, price: 3_800))
    }

    func testPercentAlertUsesCooldown() throws {
        let alert = PriceAlert(symbol: "BTCUSD", condition: .percentChange, direction: .cross,
                               targetValue: 1, basePrice: 60_000)
        XCTAssertNil(AlertEvaluator.fire(alert, price: 60_500))
        let fired = try XCTUnwrap(AlertEvaluator.fire(alert, price: 60_700))
        XCTAssertTrue(fired.enabled, "Cảnh báo % giữ bật")
        XCTAssertEqual(fired.triggerCount, 1)
        XCTAssertNil(AlertEvaluator.fire(fired, price: 61_000), "Trong cooldown không kích hoạt lại")
        let later = fired.lastTriggeredAt!.addingTimeInterval(AlertEvaluator.cooldown + 60)
        XCTAssertNotNil(AlertEvaluator.fire(fired, price: 61_000, now: later))
    }

    func testAlertTexts() {
        let alert = PriceAlert(symbol: "XAUUSD", condition: .price, direction: .above,
                               targetValue: 4_050, basePrice: 4_000, note: "Vàng")
        XCTAssertEqual(alert.displayTarget, "4050.00")
        XCTAssertEqual(alert.conditionText, "≥ 4050.00")
        XCTAssertTrue(alert.notificationBody(price: 4_060).contains("XAU/USD"))
        XCTAssertTrue(alert.notificationBody(price: 4_060).contains("4050.00"))

        let percent = PriceAlert(symbol: "EURUSD", condition: .percentChange, direction: .cross,
                                 targetValue: 0.5, basePrice: 1.10)
        XCTAssertEqual(percent.displayTarget, "±0.50%")
        XCTAssertTrue(percent.notificationBody(price: 1.2).contains("9.09%"))
    }

    func testAlertStoreRoundTrip() {
        let alert = PriceAlert(symbol: "XAUUSD", condition: .price, direction: .above, targetValue: 4_000)
        PriceAlertStore.save([alert])
        XCTAssertEqual(PriceAlertStore.load(), [alert])
        PriceAlertStore.save([])
        XCTAssertEqual(PriceAlertStore.load(), [])
    }

    // MARK: - Trader API

    func testInstrumentsParsingAcceptsMultipleShapes() {
        XCTAssertEqual(TradingClient.parseInstruments(Data(#"{"instruments":["XAUUSD","EURUSD"]}"#.utf8)),
                       ["EURUSD", "XAUUSD"])
        XCTAssertEqual(TradingClient.parseInstruments(Data(#"["BTCUSD"]"#.utf8)), ["BTCUSD"])
        XCTAssertEqual(TradingClient.parseInstruments(
            Data(#"{"data":[{"instrument":"XAGUSD"},{"symbol":"USOIL"},"NGAS"]}"#.utf8)),
            ["NGAS", "USOIL", "XAGUSD"])
        XCTAssertEqual(TradingClient.parseInstruments(Data("not json".utf8)), [])
    }

    func testAccessPointNormalizationAndTicksURL() {
        XCTAssertEqual(PulseCredentials.normalizeAccessPoint("https://tt.example.com/"), "tt.example.com")
        XCTAssertEqual(PulseCredentials.normalizeAccessPoint(" wss://tt.example.com/v1/x "), "tt.example.com")

        let credentials = PulseCredentials(partnerHost: "", apiKey: "", privateKey: "",
                                           tradingHost: "https://gw.example.com", accountId: "12345",
                                           accessPoint: "https://tt.example.com")
        XCTAssertTrue(credentials.isTradingConfigured)
        XCTAssertFalse(credentials.isPartnerConfigured)
        XCTAssertEqual(credentials.ticksURL()?.absoluteString,
                       "wss://tt.example.com/v1/server-events/accounts/12345/ws/ticks")
        XCTAssertNil(PulseCredentials(tradingHost: "https://gw", accountId: "1").ticksURL())
    }

    func testSeparateTradingKeyFallsBackToSharedKey() {
        let shared = PulseCredentials(partnerHost: "https://api.exness.com", apiKey: "k", privateKey: "p",
                                      tradingHost: "https://gw", accountId: "7")
        XCTAssertEqual(shared.tradingCredentials?.apiKey, "k")
        let separate = PulseCredentials(partnerHost: "https://api.exness.com", apiKey: "k", privateKey: "p",
                                        tradingHost: "https://gw", accountId: "7",
                                        tradingAPIKey: "k2", tradingPrivateKey: "p2")
        XCTAssertEqual(separate.tradingCredentials?.apiKey, "k2")
        XCTAssertEqual(separate.partnerClient?.credentials.apiKey, "k")
    }

    func testTradingBaseURLPrefersAccessPoint() {
        var credentials = PulseCredentials(tradingHost: "https://gw.example.com", accountId: "1",
                                           apiKey: "k", privateKey: "p")
        XCTAssertEqual(credentials.tradingBaseURL, "https://gw.example.com")
        XCTAssertEqual(credentials.tradingGatewayCredentials?.baseURL, "https://gw.example.com")

        credentials.accessPoint = "https://tt.example.com/"
        XCTAssertEqual(credentials.tradingBaseURL, "https://tt.example.com")
        XCTAssertEqual(credentials.tradingCredentials?.baseURL, "https://tt.example.com")
        XCTAssertEqual(credentials.tradingGatewayCredentials?.baseURL, "https://gw.example.com",
                       "Discovery luôn đi qua gateway")
    }

    func testAPIInstrumentMapsAccountSuffix() {
        let instruments = ["XAUUSDm", "EURUSDm", "BTCUSDm", "GBPUSD"]
        XCTAssertEqual(PulseSymbol.apiInstrument("XAUUSD", in: instruments), "XAUUSDm")
        XCTAssertEqual(PulseSymbol.apiInstrument("GBPUSD", in: instruments), "GBPUSD")
        XCTAssertEqual(PulseSymbol.apiInstrument("GBPUSD", in: []), "GBPUSD")
        XCTAssertEqual(PulseSymbol.apiInstrument("USDJPY", in: instruments), "USDJPY", "Không có thì giữ nguyên")
        XCTAssertEqual(PulseSymbol.baseSymbol("XAUUSDm", in: ["XAUUSD", "EURUSD"]), "XAUUSD")
        XCTAssertNil(PulseSymbol.baseSymbol("XAGUSDm", in: ["XAUUSD"]))
        XCTAssertNil(PulseSymbol.baseSymbol("XAUUSD", in: ["XAUUSD"]), "Trùng chính nó không cần alias")
    }

    func testTickParsingAcceptsNumbersStringsAndEpoch() throws {
        let numeric = try XCTUnwrap(TickStream.parse(
            data: Data(#"{"instrument":"xauusd","bid":4050.12,"ask":4050.32,"timestamp":"2026-11-23T10:00:00Z"}"#.utf8)))
        XCTAssertEqual(numeric.symbol, "XAUUSD")
        XCTAssertEqual(numeric.mid, 4050.22, accuracy: 0.0001)
        XCTAssertEqual(numeric.spread, 0.2, accuracy: 0.0001)
        XCTAssertNotNil(numeric.timestamp)

        let loose = try XCTUnwrap(TickStream.parse(
            data: Data(#"{"instrument":"EURUSD","bid":"1.1000","ask":"1.1002","timestamp":1795428000000}"#.utf8)))
        XCTAssertEqual(loose.bid, 1.1)
        XCTAssertEqual(loose.ask, 1.1002)
        XCTAssertEqual(loose.timestamp?.timeIntervalSince1970 ?? 0, 1_795_428_000, accuracy: 0.001)

        XCTAssertNil(TickStream.parse(data: Data(#"{"instrument":"EURUSD","bid":"abc","ask":"1.1"}"#.utf8)))
        XCTAssertNil(TickStream.parse(data: Data("{}".utf8)))
    }

    // MARK: - Cấu hình nguồn tin

    func testNewsSourcesFilterDisabledCategories() {
        NewsSources.setDisabledCategories([.crypto])
        NewsSources.setCustomFeeds([NewsFeed(url: "https://example.com/rss", title: "Mine", category: .custom)])
        let feeds = NewsSources.enabledFeeds()
        XCTAssertFalse(feeds.contains { $0.category == .crypto })
        XCTAssertTrue(feeds.contains { $0.title == "Mine" })
        XCTAssertTrue(feeds.contains { $0.url == "https://investinglive.com/feed/news" })
        NewsSources.setDisabledCategories([])
        NewsSources.setCustomFeeds([])
    }

    func testCalendarReminderNotificationIdIsStable() {
        let id = "USD|CPI|1700000000"
        XCTAssertEqual(CalendarReminderStore.notificationId(for: id), "pulse.event.USD_CPI_1700000000")
        CalendarReminderStore.set(minutes: 15, for: id)
        XCTAssertEqual(CalendarReminderStore.minutes(for: id), 15)
        CalendarReminderStore.set(minutes: nil, for: id)
        XCTAssertNil(CalendarReminderStore.minutes(for: id))
    }
}
