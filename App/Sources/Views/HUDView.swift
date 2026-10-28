import SwiftUI

/// HUD toàn màn hình khi lái xe: tốc độ hiện tại, biển giới hạn, cảnh báo kế tiếp
/// và chỉ dẫn rẽ — chữ lớn, nền tối, dùng được khi gắn điện thoại lên xe.
@MainActor
struct HUDView: View {
    @ObservedObject var model: MapViewModel
    @ObservedObject var settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppTheme.hudGradient.ignoresSafeArea()

            // Quầng sáng màu theo trạng thái tốc độ.
            Circle()
                .fill((model.speedContext.isOverLimit ? AppTheme.danger : AppTheme.cyan).opacity(0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(y: -70)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 14) {
                topBar
                speedSection
                if let alert = model.nextAlert {
                    alertCard(alert)
                }
                stepSection
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            pulse = true
            model.presentHUD()
        }
    }

    // MARK: - Thanh trên

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isNavigating ? "ĐANG DẪN ĐƯỜNG" : "HUD TỐC ĐỘ")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(AppTheme.cyan)
                Text(model.destination?.name ?? model.speedContext.roadName ?? "Chưa chọn điểm đến")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            Button {
                model.stopNavigation()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng HUD")
        }
    }

    // MARK: - Tốc độ

    private var speedSection: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: -6) {
                Text("\(Int(model.speedContext.speedKmh.rounded()))")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.speedContext.isOverLimit
                                     ? Color(red: 1.0, green: 0.42, blue: 0.38)
                                     : Color.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("km/h")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if let limit = model.speedContext.limit {
                ZStack {
                    if model.speedContext.isOverLimit {
                        Circle()
                            .stroke(Color(red: 1.0, green: 0.35, blue: 0.32).opacity(0.55), lineWidth: 4)
                            .frame(width: 108, height: 108)
                            .scaleEffect(pulse ? 1.12 : 1.0)
                            .opacity(pulse ? 0.2 : 0.9)
                    }
                    SpeedLimitSignView(limit: limit, size: 88)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 26))
                    Text("chưa rõ\nbiển báo")
                        .font(.system(size: 10, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color.white.opacity(0.06)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Cảnh báo kế tiếp

    private func alertCard(_ alert: ActiveAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.alert.kind.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(alert.alert.kind.tint))

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.alert.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(alert.distanceText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(alert.isImminent ? Color(red: 1.0, green: 0.55, blue: 0.35) : .white.opacity(0.7))
                    if let limit = alert.alert.speedLimit {
                        Text("· giới hạn \(limit) km/h")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            Spacer(minLength: 0)

            if alert.isImminent {
                Text("CHÚ Ý")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.alertGradient))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.hudCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(alert.isImminent
                                ? AppTheme.danger.opacity(0.55)
                                : Color.white.opacity(0.08),
                                lineWidth: 1)
                )
        )
    }

    // MARK: - Chỉ dẫn

    private var stepSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let step = model.currentStep {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.accentGradient)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.instruction)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(step.formattedDistance)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Chưa có tuyến đường. Hãy chọn điểm đến trên bản đồ.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
            }

            if let next = model.nextStep {
                Text("Sau đó: \(next.instruction)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }

            HStack(spacing: 16) {
                Label(Format.hudDistance(remainingDistance), systemImage: "arrow.triangle.turn.up.right.diamond")
                Label(Format.duration(remainingTime), systemImage: "clock")
                Label("\(model.routeAlerts.count)", systemImage: "exclamationmark.triangle")
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.hudCard)
        )
    }

    // MARK: - Nút dưới

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                settings.voiceAlerts.toggle()
            } label: {
                Label(settings.voiceAlerts ? "Giọng nói" : "Im lặng",
                      systemImage: settings.voiceAlerts ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            Button {
                model.stopNavigation()
                dismiss()
            } label: {
                Text("Kết thúc")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(AppTheme.alertGradient)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Số liệu còn lại

    private var remainingDistance: Double {
        guard let route = model.selectedRoute else { return 0 }
        let steps = route.steps
        guard !steps.isEmpty else { return route.distance }
        let index = min(max(model.navigationStepIndex, 0), steps.count - 1)
        return steps[index...].reduce(0) { $0 + $1.distance }
    }

    private var remainingTime: TimeInterval {
        guard let route = model.selectedRoute, route.distance > 0 else { return 0 }
        return route.expectedTravelTime * (remainingDistance / route.distance)
    }
}
