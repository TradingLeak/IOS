import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: PulseStore

    private let features: [(symbol: String, tint: Color, title: String, detail: String)] = [
        ("chart.line.uptrend.xyaxis", PulseTheme.teal,
         "Giá trực tiếp từ Exness",
         "WebSocket ticks + nến giá nhiều khung thời gian, sparkline và biểu đồ nến."),
        ("calendar", PulseTheme.danger,
         "Lịch kinh tế miễn phí",
         "Sự kiện Forex Factory theo tuần, lọc theo mức ảnh hưởng & tiền tệ, nhắc trước khi phát hành."),
        ("newspaper.fill", PulseTheme.violet,
         "Tin tức nhiều nguồn",
         "FXStreet, InvestingLive, CoinDesk, Fed — gộp, tìm kiếm, đọc ngay trong app."),
        ("bell.badge.fill", PulseTheme.warning,
         "Cảnh báo giá",
         "Đặt mức giá hoặc biên độ %, nhận thông báo hệ thống kể cả khi app không mở."),
        ("person.2.fill", PulseTheme.gold,
         "Hoa hồng đối tác",
         "Tổng hợp hoa hồng, khách hàng và cấp bậc từ Partnership API.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 28)

                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(PulseTheme.brandGradient)
                            .frame(width: 88, height: 88)
                            .shadow(color: PulseTheme.teal.opacity(0.35), radius: 24, y: 10)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                    Text("Pulse")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(PulseTheme.textPrimary)
                    Text("Đối tác · Giao dịch · Lịch kinh tế · Tin tức")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulseTheme.textSecondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                        HStack(alignment: .top, spacing: 14) {
                            PulseIconBadge(symbol: feature.symbol, tint: feature.tint, size: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(feature.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(PulseTheme.textPrimary)
                                Text(feature.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(PulseTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if index < features.count - 1 {
                            Divider().overlay(PulseTheme.stroke).padding(.leading, 68)
                        }
                    }
                }
                .pulseGlass()

                NavigationLink(destination: SettingsView()) {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").font(.system(size: 15, weight: .bold))
                        Text("Kết nối API Exness")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(PulseTheme.brandGradient)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    store.enterGuestMode()
                } label: {
                    Text("Xem trước không cần API (lịch + tin tức)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulseTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Text("API key và private key chỉ lưu trong Keychain của máy, không gửi đi đâu khác ngoài Exness. Lịch kinh tế và tin tức dùng nguồn công khai, miễn phí, không cần key.")
                    .font(.system(size: 11))
                    .foregroundStyle(PulseTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(24)
        }
        .navigationBarHidden(true)
    }
}
