import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var store: PulseStore
    @Environment(\.dismiss) private var dismiss

    // Partnership
    @State private var partnerHost = ""
    @State private var apiKey = ""
    @State private var privateKey = ""

    // Trader API
    @State private var tradingHost = ""
    @State private var accountId = ""
    @State private var useSeparateTradingKey = false
    @State private var tradingAPIKey = ""
    @State private var tradingPrivateKey = ""

    // Trạng thái
    @State private var showKeys = false
    @State private var testResult = ""
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var disabledCategories: Set<NewsCategory> = []
    @State private var customFeeds: [NewsFeed] = []
    @State private var showAddFeed = false
    @State private var loaded = false

    private var partnerValidationError: String? {
        guard !partnerHost.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ExnessCredentials(baseURL: partnerHost, apiKey: apiKey, privateKey: privateKey).hostValidationError
    }

    private var tradingValidationError: String? {
        guard !tradingHost.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let key = useSeparateTradingKey ? tradingAPIKey : apiKey
        let priv = useSeparateTradingKey ? tradingPrivateKey : privateKey
        return ExnessCredentials(baseURL: tradingHost, apiKey: key, privateKey: priv).hostValidationError
    }

    private var canSave: Bool {
        let hasPartner = !partnerHost.isEmpty && !apiKey.isEmpty && !privateKey.isEmpty
        let hasTrading = !tradingHost.isEmpty && !accountId.isEmpty && (!useSeparateTradingKey || (!tradingAPIKey.isEmpty && !tradingPrivateKey.isEmpty))
        return (hasPartner || hasTrading) && partnerValidationError == nil && tradingValidationError == nil
    }

    var body: some View {
        Form {
            partnershipSection
            tradingSection
            actionsSection
            notificationsSection
            newsSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(PulseTheme.background)
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") { dismiss() }
                    .foregroundStyle(PulseTheme.teal)
            }
        }
        .task {
            if !loaded {
                load()
                loaded = true
            }
            permission = await AlertNotifier.shared.authorizationStatus()
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedSheet(feeds: $customFeeds)
        }
    }

    // MARK: - Nạp giá trị

    private func load() {
        if let credentials = store.credentials {
            partnerHost = credentials.partnerHost
            apiKey = credentials.apiKey
            privateKey = credentials.privateKey
            tradingHost = credentials.tradingHost
            accountId = credentials.accountId
            tradingAPIKey = credentials.tradingAPIKey
            tradingPrivateKey = credentials.tradingPrivateKey
            useSeparateTradingKey = !credentials.tradingAPIKey.isEmpty || !credentials.tradingPrivateKey.isEmpty
        }
        disabledCategories = NewsSources.disabledCategories()
        customFeeds = NewsSources.customFeeds()
    }

    // MARK: - Partnership

    private var partnershipSection: some View {
        Section {
            TextField("https://api.exness.com", text: $partnerHost)
                .textContentType(.URL)
                .keyboardType(.URL)
                .foregroundStyle(PulseTheme.textPrimary)
            TextField("API key (exnsk-…)", text: $apiKey)
                .textContentType(.password)
                .foregroundStyle(PulseTheme.textPrimary)
            SecureField("Private key (128 ký tự hex hoặc PEM)", text: $privateKey)
                .foregroundStyle(PulseTheme.textPrimary)
            if let message = partnerValidationError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(PulseTheme.danger)
            }
        } header: {
            Label("Partnership API (hoa hồng đối tác)", systemImage: "person.2.fill")
                .foregroundStyle(PulseTheme.gold)
        } footer: {
            Text("Tạo key tại my.exness.partners → Settings → API management, scope Read-only. Host là địa chỉ trong DNS widget (bắt đầu bằng https://). Để trống nếu chỉ dùng Trader API.")
                .font(.system(size: 11))
        }
    }

    // MARK: - Trader API

    private var tradingSection: some View {
        Section {
            TextField("https://<gateway>.exness.io", text: $tradingHost)
                .textContentType(.URL)
                .keyboardType(.URL)
                .foregroundStyle(PulseTheme.textPrimary)
            TextField("Account ID (chuỗi số)", text: $accountId)
                .keyboardType(.numberPad)
                .foregroundStyle(PulseTheme.textPrimary)
            Toggle("Dùng API key riêng cho Trader API", isOn: $useSeparateTradingKey)
                .tint(PulseTheme.teal)
            if useSeparateTradingKey {
                TextField("Trading API key", text: $tradingAPIKey)
                    .foregroundStyle(PulseTheme.textPrimary)
                SecureField("Trading private key", text: $tradingPrivateKey)
                    .foregroundStyle(PulseTheme.textPrimary)
            }
            if let message = tradingValidationError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(PulseTheme.danger)
            }
            if let point = store.credentials?.accessPoint {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(PulseTheme.teal)
                    Text("Access point: " + point)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(PulseTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Label("Trader API (giá, tài khoản, giao dịch)", systemImage: "chart.line.uptrend.xyaxis")
                .foregroundStyle(PulseTheme.violet)
        } footer: {
            Text("Key cần scope Trading (Read-only đủ để xem giá/tài khoản). Host gateway và Account ID lấy trong Personal Area → API. App tự phát hiện access point cho WebSocket khi kiểm tra kết nối.")
                .font(.system(size: 11))
        }
    }

    // MARK: - Hành động

    private var actionsSection: some View {
        Section {
            PulsePrimaryButton(title: "Lưu & kiểm tra kết nối",
                               symbol: "checkmark.seal.fill",
                               isLoading: store.isTesting,
                               isEnabled: canSave) {
                Task { await saveAndTest() }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if !testResult.isEmpty {
                Text(testResult)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(testResult.contains("✗") ? PulseTheme.warning : PulseTheme.success)
                    .textSelection(.enabled)
            }

            Button(role: .destructive) {
                store.signOut()
                clearFields()
                testResult = "Đã xoá thông tin đăng nhập khỏi Keychain."
            } label: {
                Label("Xoá thông tin đăng nhập", systemImage: "trash")
                    .foregroundStyle(PulseTheme.danger)
            }

            if store.guestMode {
                Button {
                    store.leaveGuestMode()
                } label: {
                    Label("Thoát chế độ chỉ xem", systemImage: "eye.slash")
                        .foregroundStyle(PulseTheme.textSecondary)
                }
            }
        } header: {
            Text("Kết nối")
        } footer: {
            Text("Thông tin được lưu trong Keychain của máy (AfterFirstUnlockThisDeviceOnly). Không bao giờ ghi log hay gửi đi nơi khác ngoài Exness.")
                .font(.system(size: 11))
        }
    }

    // MARK: - Thông báo

    private var notificationsSection: some View {
        Section {
            Toggle("Thông báo cảnh báo giá", isOn: Binding(
                get: { AlertNotifier.shared.isEnabled },
                set: { AlertNotifier.shared.setEnabled($0) }
            ))
            .tint(PulseTheme.teal)
            HStack {
                Text("Quyền thông báo")
                    .foregroundStyle(PulseTheme.textSecondary)
                Spacer()
                Text(permissionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(permission == .authorized ? PulseTheme.success : PulseTheme.warning)
            }
            if permission == .notDetermined || permission == .denied {
                Button("Cấp quyền thông báo") {
                    Task {
                        _ = await AlertNotifier.shared.requestAuthorization()
                        permission = await AlertNotifier.shared.authorizationStatus()
                        if permission == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                            _ = await UIApplication.shared.open(url)
                        }
                    }
                }
                .foregroundStyle(PulseTheme.teal)
            }
        } header: {
            Label("Thông báo", systemImage: "bell.badge.fill")
                .foregroundStyle(PulseTheme.warning)
        } footer: {
            Text("Khi app đóng, iOS định kỳ đánh thức để kiểm tra cảnh báo (Cài đặt → Pulse → Background App Refresh). Cảnh báo theo % cách nhau tối thiểu 60 phút.")
                .font(.system(size: 11))
        }
    }

    private var permissionTitle: String {
        switch permission {
        case .authorized, .provisional, .ephemeral: return "Đã cấp"
        case .denied: return "Bị từ chối"
        default: return "Chưa xác định"
        }
    }

    // MARK: - Nguồn tin

    private var newsSection: some View {
        Section {
            ForEach(NewsCategory.allCases) { category in
                let feeds = NewsSources.builtIn.filter { $0.category == category }
                let custom = customFeeds.filter { $0.category == category }
                if !feeds.isEmpty || !custom.isEmpty {
                    Toggle(isOn: Binding(
                        get: { !disabledCategories.contains(category) },
                        set: { enabled in
                            if enabled {
                                disabledCategories.remove(category)
                            } else {
                                disabledCategories.insert(category)
                            }
                            NewsSources.setDisabledCategories(disabledCategories)
                            Task { await store.loadNews(force: true) }
                        }
                    )) {
                        Label(category.title, systemImage: category.symbol)
                            .foregroundStyle(PulseTheme.textPrimary)
                    }
                    .tint(category.tint)
                    ForEach(custom) { feed in
                        HStack {
                            Text(feed.title)
                                .font(.system(size: 12))
                                .foregroundStyle(PulseTheme.textSecondary)
                            Spacer()
                            Button {
                                customFeeds.removeAll { $0.id == feed.id }
                                NewsSources.setCustomFeeds(customFeeds)
                                Task { await store.loadNews(force: true) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(PulseTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button {
                showAddFeed = true
            } label: {
                Label("Thêm nguồn RSS/Atom", systemImage: "plus.circle.fill")
                    .foregroundStyle(PulseTheme.teal)
            }
        } header: {
            Label("Nguồn tin tức", systemImage: "newspaper.fill")
                .foregroundStyle(PulseTheme.violet)
        } footer: {
            Text("Nguồn mặc định: FXStreet, InvestingLive, CoinDesk, Federal Reserve — đều là RSS công khai, không cần key.")
                .font(.system(size: 11))
        }
    }

    // MARK: - Giới thiệu

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Phiên bản")
                    .foregroundStyle(PulseTheme.textSecondary)
                Spacer()
                Text(versionText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(PulseTheme.textPrimary)
            }
            HStack {
                Text("Lịch kinh tế")
                    .foregroundStyle(PulseTheme.textSecondary)
                Spacer()
                Text("Forex Factory · miễn phí")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textPrimary)
            }
            HStack {
                Text("Giá & giao dịch")
                    .foregroundStyle(PulseTheme.textSecondary)
                Spacer()
                Text("Exness Trader API")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textPrimary)
            }
        } header: {
            Text("Giới thiệu")
        } footer: {
            Text("Pulse không phải ứng dụng chính thức của Exness. Dữ liệu chỉ mang tính tham khảo, không phải khuyến nghị đầu tư.")
                .font(.system(size: 11))
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Pulse \(version) (\(build))"
    }

    // MARK: - Lưu

    private func clearFields() {
        partnerHost = ""
        apiKey = ""
        privateKey = ""
        tradingHost = ""
        accountId = ""
        tradingAPIKey = ""
        tradingPrivateKey = ""
        useSeparateTradingKey = false
    }

    private func saveAndTest() async {
        let credentials = PulseCredentials(
            partnerHost: partnerHost.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKey: privateKey,
            tradingHost: tradingHost.trimmingCharacters(in: .whitespacesAndNewlines),
            accountId: accountId.trimmingCharacters(in: .whitespacesAndNewlines),
            tradingAPIKey: useSeparateTradingKey ? tradingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            tradingPrivateKey: useSeparateTradingKey ? tradingPrivateKey : "",
            accessPoint: store.credentials?.accessPoint
        )
        do {
            try store.save(credentials)
        } catch {
            testResult = "✗ " + error.localizedDescription
            return
        }
        testResult = await store.testConnection()
        if credentials.isTradingConfigured {
            await store.loadAccount()
            await store.loadCandles()
        }
        if credentials.isPartnerConfigured {
            await store.loadPartner()
        }
    }
}

// MARK: - Thêm nguồn RSS riêng

struct AddFeedSheet: View {
    @Binding var feeds: [NewsFeed]
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    @State private var category: NewsCategory = .custom
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nguồn RSS/Atom") {
                    TextField("Tên hiển thị", text: $title)
                        .foregroundStyle(PulseTheme.textPrimary)
                    TextField("https://example.com/rss", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .foregroundStyle(PulseTheme.textPrimary)
                    Picker("Nhóm", selection: $category) {
                        ForEach(NewsCategory.allCases.filter { $0 == .custom || $0 == .forex }) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(PulseTheme.danger)
                    }
                }
                Section {
                    PulsePrimaryButton(title: "Thêm nguồn", symbol: "plus") { add() }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulseTheme.background)
            .navigationTitle("Thêm nguồn tin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                        .foregroundStyle(PulseTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func add() {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmedURL), let scheme = parsed.scheme,
              scheme.lowercased() == "https", parsed.host != nil else {
            error = "URL phải bắt đầu bằng https://"
            return
        }
        guard !feeds.contains(where: { $0.url == trimmedURL }) else {
            error = "Nguồn này đã có trong danh sách."
            return
        }
        let feed = NewsFeed(url: trimmedURL,
                            title: title.trimmingCharacters(in: .whitespaces).isEmpty ? (parsed.host ?? "RSS") : title,
                            category: category)
        feeds.append(feed)
        NewsSources.setCustomFeeds(feeds)
        dismiss()
    }
}
