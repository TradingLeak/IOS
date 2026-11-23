import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var store: PartnerStore

    @State private var host = ""
    @State private var apiKey = ""
    @State private var privateKey = ""
    @State private var loaded = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false
    @State private var showDeleteConfirm = false

    @AppStorage(PaymentNotifier.enabledKey) private var notificationsEnabled = true
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var checkMessage: String?
    @State private var isCheckingPayments = false
    @Environment(\.scenePhase) private var scenePhase

    private let managementURL = URL(string: "https://my.exness.partners/settings/api-management")
    private let docsURL = URL(string: "https://www.exness-api.com/partnership/get-started")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    notificationsCard
                    credentialsCard
                    securityCard
                    dangerCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { loadCredentialsIfNeeded() }
            .task { notificationStatus = await PaymentNotifier.shared.authorizationStatus() }
            .onChange(of: scenePhase) { phase in
                // Người dùng vừa quay lại từ app Cài đặt → đọc lại quyền thông báo.
                guard phase == .active else { return }
                Task { notificationStatus = await PaymentNotifier.shared.authorizationStatus() }
            }
            .confirmationDialog("Xoá thông tin đăng nhập?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Xoá và đăng xuất", role: .destructive) {
                    store.signOut()
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("API key, private key và toàn bộ dữ liệu đã tải sẽ bị xoá khỏi thiết bị.")
            }
        }
    }

    // MARK: - Trạng thái

    private var statusCard: some View {
        PanelCard(title: "Trạng thái kết nối", symbol: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 12) {
                connectionRow("API host", store.credentials?.normalizedBaseURL ?? "—")
                connectionRow("API key", store.credentials?.maskedAPIKey ?? "—")

                if let link = store.defaultLink {
                    connectionRow("Link giới thiệu", link.code)
                }
                if let tier = store.tierState {
                    connectionRow("Cấp bậc", tier.tierName)
                }
                if let updated = store.lastUpdated {
                    connectionRow("Cập nhật lần cuối", Fmt.dateTime(updated))
                }

                HStack(spacing: 10) {
                    SecondaryActionButton(title: "Kiểm tra kết nối", symbol: "bolt.horizontal") {
                        Task { await testConnection() }
                    }
                    SecondaryActionButton(title: "Làm mới", symbol: "arrow.clockwise", tint: PartnerTheme.info) {
                        Task { await store.refreshAll() }
                    }
                }

                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? PartnerTheme.danger : PartnerTheme.success)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func connectionRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(PartnerTheme.textSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PartnerTheme.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Thông báo thanh toán

    private var notificationsCard: some View {
        PanelCard(title: "Thông báo thanh toán", symbol: "bell.badge.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bật thông báo khi có khoản thanh toán")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PartnerTheme.textPrimary)
                        Text("Pop-up trong app khi đang mở; thông báo hệ thống khi app chạy nền.")
                            .font(.system(size: 10))
                            .foregroundStyle(PartnerTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(PartnerTheme.accent)
                .onChange(of: notificationsEnabled) { enabled in
                    guard enabled else { return }
                    Task { await requestNotificationPermission() }
                }

                if notificationsEnabled {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thông báo hệ thống")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PartnerTheme.textSecondary)
                            Text(notificationStatusText)
                                .font(.system(size: 11))
                                .foregroundStyle(notificationStatusColor)
                        }
                        Spacer(minLength: 8)
                        if notificationStatus == .notDetermined {
                            SecondaryActionButton(title: "Cấp quyền", symbol: "bell") {
                                Task { await requestNotificationPermission() }
                            }
                            .frame(width: 118)
                        } else if notificationStatus == .denied {
                            SecondaryActionButton(title: "Mở Cài đặt", symbol: "gear", tint: PartnerTheme.info) {
                                openSystemSettings()
                            }
                            .frame(width: 128)
                        }
                    }

                    connectionRow("Kiểm tra nền", "≈30–60 phút/lần, do iOS quyết định")
                    connectionRow("Kiểm tra lần cuối",
                                   store.lastPaymentCheck.map { Fmt.dateTime($0) } ?? "Chưa")
                    Text("Khi app đóng, iOS chỉ đánh thức nếu bật Background App Refresh (Cài đặt → Chung) và app được dùng thường xuyên.")
                        .font(.system(size: 10))
                        .foregroundStyle(PartnerTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecondaryActionButton(title: "Kiểm tra thanh toán ngay",
                                           symbol: "arrow.clockwise",
                                           tint: PartnerTheme.info) {
                        Task { await checkPaymentsNow() }
                    }
                    .disabled(isCheckingPayments)
                    .opacity(isCheckingPayments ? 0.5 : 1)

                    if let checkMessage {
                        Text(checkMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(PartnerTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "Đã cho phép"
        case .denied: return "Bị từ chối — bật lại trong Cài đặt hệ thống"
        case .notDetermined: return "Chưa cấp quyền"
        @unknown default: return "Không rõ"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return PartnerTheme.success
        case .denied: return PartnerTheme.danger
        default: return PartnerTheme.textSecondary
        }
    }

    // MARK: - Chỉnh sửa

    private var credentialsCard: some View {
        PanelCard(title: "Cập nhật thông tin", symbol: "key.horizontal.fill") {
            VStack(alignment: .leading, spacing: 16) {
                CredentialField(title: "API host",
                                placeholder: "https://<api-host>",
                                text: $host,
                                keyboard: .URL)
                CredentialField(title: "API key",
                                placeholder: store.credentials?.maskedAPIKey ?? "exnsk-…",
                                text: $apiKey,
                                keyboard: .asciiCapable,
                                isSecure: true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("PRIVATE KEY MỚI")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(PartnerTheme.textSecondary)
                        Spacer()
                        if let current = store.credentials?.privateKey, !current.isEmpty {
                            Text("đã lưu")
                                .font(.system(size: 10))
                                .foregroundStyle(PartnerTheme.success)
                        }
                    }
                    TextEditor(text: $privateKey)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PartnerTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(PartnerTheme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PartnerTheme.stroke)
                        )
                    Text("Để trống các trường không muốn đổi.")
                        .font(.system(size: 10))
                        .foregroundStyle(PartnerTheme.textTertiary)
                }

                PrimaryActionButton(title: "Lưu thay đổi",
                                     symbol: "checkmark.circle.fill",
                                     isLoading: isWorking,
                                     isEnabled: canSave) {
                    Task { await save() }
                }
            }
        }
    }

    private var canSave: Bool {
        !isWorking && (!host.trimmingCharacters(in: .whitespaces).isEmpty ||
                       !apiKey.trimmingCharacters(in: .whitespaces).isEmpty ||
                       !privateKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Bảo mật

    private var securityCard: some View {
        PanelCard(title: "Bảo mật", symbol: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 10) {
                securityRow("Nên tạo API key với quyền Partnership → Read-only. App không cần quyền ghi.")
                securityRow("Private key và API key lưu trong Keychain, chỉ đọc được trên thiết bị này.")
                securityRow("Mọi yêu cầu được ký Ed25519 ngay trên máy rồi mới gửi tới Exness; app không gửi key cho máy chủ khác.")
                securityRow("Exness khuyến nghị giữ private key ở backend. Nếu dùng cho đội nhóm lớn, nên dựng một proxy backend và để app gọi proxy đó.")
            }
        }
    }

    private func securityRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(PartnerTheme.success)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(PartnerTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Xoá dữ liệu

    private var dangerCard: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13))
                Text("Xoá thông tin đăng nhập")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(PartnerTheme.danger)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PartnerTheme.danger.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PartnerTheme.danger.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Giới thiệu

    private var aboutCard: some View {
        PanelCard(title: "Giới thiệu", symbol: "info.circle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                connectionRow("Phiên bản", appVersion)
                Text("PartnerHub là công cụ độc lập, KHÔNG phải ứng dụng chính thức của Exness. Dữ liệu được đọc trực tiếp từ Partnership API của tài khoản đối tác của bạn.")
                    .font(.system(size: 11))
                    .foregroundStyle(PartnerTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let managementURL {
                    Link(destination: managementURL) {
                        Label("Trang API Management", systemImage: "safari")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PartnerTheme.accent)
                    }
                }
                if let docsURL {
                    Link(destination: docsURL) {
                        Label("Tài liệu Partnership API", systemImage: "book")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PartnerTheme.accent)
                    }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return version + " (" + build + ")"
    }

    // MARK: - Actions

    private func loadCredentialsIfNeeded() {
        guard !loaded, let credentials = store.credentials else { return }
        host = credentials.baseURL
        loaded = true
    }

    private func currentCredentials() -> ExnessCredentials {
        let existing = store.credentials
        let newHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let newKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPrivate = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return ExnessCredentials(
            baseURL: newHost.isEmpty ? (existing?.baseURL ?? "") : newHost,
            apiKey: newKey.isEmpty ? (existing?.apiKey ?? "") : newKey,
            privateKey: newPrivate.isEmpty ? (existing?.privateKey ?? "") : newPrivate
        )
    }

    @MainActor private func testConnection() async {
        isWorking = true
        defer { isWorking = false }
        message = nil

        do {
            let link = try await store.testConnection(with: currentCredentials())
            isError = false
            message = "Kết nối thành công — link giới thiệu: \(link.code)"
        } catch {
            isError = true
            message = PartnerStore.message(for: error)
        }
    }

    @MainActor private func checkPaymentsNow() async {
        isCheckingPayments = true
        defer { isCheckingPayments = false }
        checkMessage = nil

        let events = await store.checkForPayments()
        if events.isEmpty {
            checkMessage = "Đã kiểm tra — chưa có khoản thanh toán mới."
        } else {
            let total = events.filter { $0.kind.isPositive }.reduce(Decimal(0)) { $0 + $1.amountUSD }
            checkMessage = "Có \(events.count) khoản mới · tổng " + Fmt.usd(total)
        }
    }

    /// Xin quyền rồi đọc lại trạng thái (requestAuthorization chỉ trả Bool).
    @MainActor private func requestNotificationPermission() async {
        await PaymentNotifier.shared.requestAuthorization()
        notificationStatus = await PaymentNotifier.shared.authorizationStatus()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor private func save() async {
        isWorking = true
        defer { isWorking = false }
        message = nil

        let credentials = currentCredentials()
        do {
            let link = try await store.testConnection(with: credentials)
            try store.save(credentials)
            store.defaultLink = link
            isError = false
            message = "Đã lưu và kết nối thành công."
            host = credentials.baseURL
            apiKey = ""
            privateKey = ""
            await store.refreshAll()
        } catch {
            isError = true
            message = PartnerStore.message(for: error)
        }
    }
}
