import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject var store: PartnerStore

    @State private var host = ""
    @State private var apiKey = ""
    @State private var privateKey = ""
    @State private var isConnecting = false
    @State private var errorText: String?

    private let managementURL = URL(string: "https://my.exness.partners/settings/api-management")

    private var canConnect: Bool {
        !trimmed(host).isEmpty &&
        !trimmed(apiKey).isEmpty &&
        !trimmed(privateKey).isEmpty &&
        !isConnecting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                stepsCard
                formCard

                if let errorText {
                    errorBanner(errorText)
                }

                PrimaryActionButton(title: "Kết nối tài khoản",
                                     symbol: "key.fill",
                                     isLoading: isConnecting,
                                     isEnabled: canConnect) {
                    Task { await connect() }
                }

                Text("Ứng dụng chỉ cần quyền Partnership → Read-only. Khóa riêng được lưu trong Keychain của thiết bị và mọi yêu cầu đều ký cục bộ trước khi gửi tới Exness.")
                    .font(.system(size: 11))
                    .foregroundStyle(PartnerTheme.textTertiary)
                    .lineSpacing(3)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Kết nối")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PartnerTheme.accentGradient)
                    .frame(width: 66, height: 66)
                    .shadow(color: PartnerTheme.accent.opacity(0.30), radius: 18, x: 0, y: 8)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.black)
            }
            .padding(.top, 6)

            Text("PartnerHub")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(PartnerTheme.textPrimary)

            Text("Theo dõi hoa hồng đối tác Exness — tổng quan, khách hàng, giao dịch và rebate trong một ứng dụng.")
                .font(.system(size: 14))
                .foregroundStyle(PartnerTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Các bước

    private var stepsCard: some View {
        PanelCard(title: "Tạo API key trong 3 bước", symbol: "list.number") {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingStep(number: 1,
                               title: "Mở API Management",
                               detail: "Đăng nhập Exness Partner → API Management → tạo API key mới.")
                OnboardingStep(number: 2,
                               title: "Chọn quyền Read-only",
                               detail: "Scope Partnership → Read-only là đủ để đọc hoa hồng, khách hàng và rebate.")
                OnboardingStep(number: 3,
                               title: "Lưu khóa riêng + API host",
                               detail: "Sao chép private key (128 ký tự hex hoặc PEM) và host trong DNS widget.")

                if let managementURL {
                    Link(destination: managementURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "safari.fill")
                            Text("Mở trang API Management")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PartnerTheme.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(PartnerTheme.accent.opacity(0.10))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Form

    private var formCard: some View {
        PanelCard(title: "Thông tin kết nối", symbol: "key.horizontal.fill") {
            VStack(alignment: .leading, spacing: 16) {
                CredentialField(title: "API host",
                                placeholder: "https://<api-host>",
                                text: $host,
                                keyboard: .URL)
                CredentialField(title: "API key",
                                placeholder: "exnsk-…",
                                text: $apiKey,
                                keyboard: .asciiCapable,
                                isSecure: true)
                privateKeyField
                Text("Host lấy từ DNS widget trong trang API Management — chỉ gồm https://<host>, không có /v1/…")
                    .font(.system(size: 10))
                    .foregroundStyle(PartnerTheme.textTertiary)
                    .lineSpacing(2)
            }
        }
    }

    private var privateKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PRIVATE KEY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(PartnerTheme.textSecondary)
                Spacer()
                Button {
                    if let pasted = UIPasteboard.general.string {
                        privateKey = pasted
                    }
                } label: {
                    Label("Dán", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PartnerTheme.accent)
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $privateKey)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(PartnerTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PartnerTheme.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PartnerTheme.stroke)
                )
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(PartnerTheme.warning)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(PartnerTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PartnerTheme.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PartnerTheme.warning.opacity(0.25))
        )
    }

    // MARK: - Actions

    @MainActor private func connect() async {
        errorText = nil
        isConnecting = true
        defer { isConnecting = false }

        let credentials = ExnessCredentials(baseURL: host, apiKey: apiKey, privateKey: privateKey)
        do {
            let link = try await store.testConnection(with: credentials)
            try store.save(credentials)
            store.defaultLink = link
            await store.refreshAll()
            // Hỏi quyền thông báo đúng lúc vừa thiết lập xong — để báo khoản thanh toán mới khi app đóng.
            if PaymentNotifier.shared.isEnabled {
                await PaymentNotifier.shared.requestAuthorization()
            }
        } catch {
            errorText = PartnerStore.message(for: error)
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Dòng bước

private struct OnboardingStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(PartnerTheme.accent))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PartnerTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(PartnerTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ô nhập

struct CredentialField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(PartnerTheme.textSecondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(PartnerTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PartnerTheme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PartnerTheme.stroke)
            )
        }
    }
}
