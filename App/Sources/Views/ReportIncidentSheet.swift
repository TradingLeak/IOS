import SwiftUI
import CoreLocation

/// Báo cáo sự cố trên đường: CSGT, tai nạn, ngập, ổ gà, cấm đường, kẹt xe.
///
/// Báo cáo **lưu trên máy** (app không có máy chủ), hiện thành marker trên bản đồ, tự hết hạn
/// theo loại và được đọc lên một lần khi bạn tới gần.
@MainActor
struct ReportIncidentSheet: View {
    @ObservedObject var model: MapViewModel
    @ObservedObject var settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: IncidentKind = .police
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    kindCard
                    locationCard
                    myReportsCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Báo cáo sự cố")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        model.clearIncidents()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.activeIncidents.isEmpty)
                    .accessibilityLabel("Xoá toàn bộ báo cáo")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { model.refreshIncidents() }
    }

    // MARK: - Chọn loại + gửi

    private var kindCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOẠI SỰ CỐ")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 8)], spacing: 8) {
                ForEach(IncidentKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(selectedKind == kind ? Color.white : kind.tint)
                            Text(kind.shortTitle)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(selectedKind == kind ? Color.white : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(kind.lifetimeText)
                                .font(.system(size: 8.5))
                                .foregroundStyle(selectedKind == kind ? Color.white.opacity(0.85) : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedKind == kind ? AnyShapeStyle(kind.tint) : AnyShapeStyle(AppTheme.subtleFill))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Ghi chú (không bắt buộc): “CSGT ở ngã tư”, “ngập 30 cm”…",
                      text: $note, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 12))
                .focused($noteFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.subtleFill)
                )

            Button {
                noteFocused = false
                model.reportIncident(selectedKind, note: note)
                note = ""
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Ghi báo cáo tại vị trí của tôi")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                    if model.location.coordinate == nil {
                        Text("chưa có GPS")
                            .font(.system(size: 10))
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .primaryGradientBackground(cornerRadius: 14)
            }
            .buttonStyle(.plain)

            Text("Báo cáo chỉ lưu trên máy bạn (không gửi lên máy chủ nào). Marker hiện ngay trên "
                 + "bản đồ và tự biến mất sau \(selectedKind.lifetimeText).")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    // MARK: - Vị trí & cảnh báo giọng nói

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.location.isAuthorized ? "location.fill" : "location.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.location.isAuthorized ? AppTheme.success : AppTheme.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.location.isAuthorized ? "Đang dùng vị trí hiện tại" : "Chưa có quyền vị trí")
                        .font(.system(size: 13, weight: .medium))
                    Text(model.location.isAuthorized
                         ? "Báo cáo được đặt đúng chỗ bạn đang đứng."
                         : "Báo cáo sẽ đặt ở tâm bản đồ đang xem.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Toggle(isOn: $settings.voiceAlerts) {
                Label("Đọc lên khi tới gần (350 m)", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 12))
            }
            .tint(AppTheme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    // MARK: - Danh sách báo cáo

    private var myReportsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BÁO CÁO CỦA TÔI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.activeIncidents.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if model.activeIncidents.isEmpty {
                Text("Chưa có báo cáo nào. Báo cáo đầu tiên sẽ hiện trên bản đồ ngay khi bạn gửi.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.activeIncidents) { report in
                    HStack(spacing: 9) {
                        Image(systemName: report.kind.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(report.kind.tint))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(report.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                            Text(report.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Button {
                            model.focus(on: report.coordinate)
                            dismiss()
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Xem trên bản đồ")

                        Button {
                            model.removeIncident(report)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Xoá báo cáo")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }
}
