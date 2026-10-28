import SwiftUI

// MARK: - Màu & biểu tượng cảnh báo

extension AlertKind {
    var tint: Color {
        switch self {
        case .speedCamera: return Color(red: 0.92, green: 0.26, blue: 0.25)
        case .redLightCamera: return Color(red: 0.85, green: 0.18, blue: 0.35)
        case .surveillanceCamera: return Color(red: 0.36, green: 0.42, blue: 0.52)
        case .speedSign, .speedZone: return Color(red: 0.90, green: 0.45, blue: 0.08)
        case .residentialZone: return Color(red: 0.20, green: 0.55, blue: 0.92)
        case .noOvertake: return Color(red: 0.55, green: 0.32, blue: 0.86)
        case .tollStation: return Color(red: 0.10, green: 0.62, blue: 0.52)
        case .schoolZone: return Color(red: 0.95, green: 0.62, blue: 0.10)
        case .checkpoint: return Color(red: 0.20, green: 0.45, blue: 0.75)
        case .hazard: return Color(red: 0.88, green: 0.35, blue: 0.12)
        case .trafficLight: return Color(red: 0.95, green: 0.40, blue: 0.15)
        case .other: return Color.gray
        }
    }
}

extension IncidentKind {
    /// Màu marker cho báo cáo sự cố — khác màu camera/biển báo để không lẫn.
    var tint: Color {
        switch self {
        case .police: return Color(red: 0.20, green: 0.45, blue: 0.85)
        case .accident: return Color(red: 0.85, green: 0.20, blue: 0.24)
        case .flooding: return Color(red: 0.13, green: 0.55, blue: 0.80)
        case .pothole: return Color(red: 0.72, green: 0.45, blue: 0.12)
        case .roadClosed: return Color(red: 0.55, green: 0.30, blue: 0.75)
        case .trafficJam: return Color(red: 0.90, green: 0.48, blue: 0.10)
        }
    }
}

extension ActiveAlert {
    var distanceText: String {
        if distance < 0 {
            return alert.kind == .speedZone ? "đang trong vùng" : "đã đi qua"
        }
        return "còn \(Format.hudDistance(distance))"
    }

    var levelColor: Color {
        switch level {
        case .close: return Color(red: 0.90, green: 0.22, blue: 0.22)
        case .approaching: return Color(red: 0.95, green: 0.60, blue: 0.08)
        case .far: return alert.kind.tint
        case .passed: return Color.secondary
        }
    }
}

// MARK: - Biển giới hạn tốc độ

/// Biển tròn viền đỏ kiểu QCVN 41:2019 (biển P.127).
struct SpeedLimitSignView: View {
    let limit: Int
    var size: CGFloat = 48
    var muted: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Circle()
                .stroke(muted ? Color.gray : Color(red: 0.83, green: 0.10, blue: 0.14),
                        lineWidth: max(3, size * 0.12))
            VStack(spacing: -size * 0.04) {
                Text("\(limit)")
                    .font(.system(size: size * 0.40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                Text("km/h")
                    .font(.system(size: size * 0.15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

struct AlertRow: View {
    let active: ActiveAlert
    var showsImage: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(active.alert.kind.tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: active.alert.kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(active.alert.kind.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(active.alert.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let limit = active.alert.speedLimit {
                        Text("\(limit)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(red: 0.83, green: 0.10, blue: 0.14)))
                    }
                }
                if !active.alert.displaySubtitle.isEmpty {
                    Text(active.alert.displaySubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(active.distanceText)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(active.levelColor)
            }

            Spacer(minLength: 0)

            if showsImage, let url = active.alert.updatedImageURL {
                CameraThumbnail(url: url)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.subtleFill)
        )
    }
}

/// Ảnh camera giao thông (tải trực tiếp từ cổng thông tin, app không lưu ảnh).
struct CameraThumbnail: View {
    let url: URL
    var size: CGFloat = 62

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholder(symbol: "camera.badge.ellipsis")
            case .empty:
                placeholder(symbol: "photo")
                    .overlay(ProgressView().controlSize(.mini))
            @unknown default:
                placeholder(symbol: "photo")
            }
        }
        .frame(width: size, height: size * 0.75)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            AppTheme.subtleFill
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Nhãn điểm

struct ScoreBadge: View {
    let score: RouteScore

    private var color: Color {
        if score.total >= 85 { return AppTheme.success }
        if score.total >= 70 { return AppTheme.accent }
        if score.total >= 55 { return AppTheme.warning }
        return AppTheme.danger
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("\(Int(score.total.rounded()))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Chip chọn nhanh loại cảnh báo trong Cài đặt.
struct AlertKindChip: View {
    let kind: AlertKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(kind.shortTitle)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isOn ? AnyShapeStyle(kind.tint) : AnyShapeStyle(AppTheme.subtleFill))
            )
        }
        .buttonStyle(.plain)
    }
}
