import SwiftUI
import UIKit

/// Pop-up đầu màn hình khi phát hiện khoản thanh toán hoa hồng mới.
/// Tự ẩn sau ~7 giây; chạm vào thẻ để mở tab Hoa hồng.
struct PaymentToastView: View {
    let event: PaymentEvent
    var extraCount: Int = 0
    var action: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.kind.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PartnerTheme.textPrimary)
                Text(event.amountText)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    if !event.dateText.isEmpty {
                        Text(event.dateText)
                    }
                    if !event.detail.isEmpty {
                        Text(event.detail)
                    }
                    if extraCount > 0 {
                        Text("+\(extraCount) khoản khác")
                            .foregroundStyle(PartnerTheme.accent)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(PartnerTheme.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PartnerTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(PartnerTheme.stroke))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng thông báo")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PartnerTheme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 18, y: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private var tint: Color {
        switch event.kind {
        case .reward: return PartnerTheme.accent
        case .rebateProcessed: return PartnerTheme.success
        case .rebateRejected, .rebateError: return PartnerTheme.warning
        }
    }
}
