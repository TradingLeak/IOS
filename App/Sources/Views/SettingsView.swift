import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: MapViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showAlertsManager = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    routingCard
                    AISettingsSection(settings: settings, model: model)
                    alertsCard
                    mapCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .sheet(isPresented: $showAlertsManager) {
                AlertsSheet(model: model, settings: settings)
            }
        }
    }

    // MARK: - Dẫn đường xe máy

    private var routingCard: some View {
        SectionCard(title: "Dẫn đường xe máy", symbol: "scooter") {
            VStack(alignment: .leading, spacing: 12) {
                InfoBanner(kind: .info,
                           text: "Tuyến đường tính bằng Apple Maps rồi chấm điểm nội bộ: loại tuyến đi cao tốc "
                                 + "(xe máy không được phép), ưu tiên đường lớn, tránh đường xấu. "
                                 + "Không dùng API bên thứ ba.")

                VStack(alignment: .leading, spacing: 3) {
                    Text("Thời gian xe máy lấy từ Apple Maps rồi hiệu chỉnh theo tuyến "
                         + "(nội đô nhanh hơn ô tô 8%, có cao tốc thì chậm hơn 2%) và luôn được "
                         + "ghi chú trong bảng so sánh tuyến.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Phương tiện mặc định")
                        .font(.system(size: 12, weight: .medium))
                    TravelModePicker(selection: $settings.defaultMode)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nhóm xe hai bánh")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Picker("Nhóm xe", selection: $settings.vehicleClass) {
                            ForEach(VehicleClass.allCases) { item in
                                Text(item.shortTitle).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    Text(settings.vehicleClass.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(settings.vehicleClass == .moped
                         ? "Xe gắn máy ≤ 50 cm³ và xe đạp điện: 40 km/h trên mọi tuyến (Thông tư 38/2024)."
                         : "Xe mô tô: 60/50 km/h trong đô thị, 70/60 km/h ngoài đô thị (Thông tư 38/2024).")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Cảnh báo trên bản đồ

    private var alertsCard: some View {
        SectionCard(title: "Cảnh báo trên bản đồ", symbol: "exclamationmark.shield") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.voiceAlerts) {
                    Label("Đọc cảnh báo bằng giọng tiếng Việt", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: $settings.showAlertPins) {
                    Label("Ghim camera/biển báo lên bản đồ", systemImage: "camera.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Ngưỡng báo vượt tốc độ")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("+\(settings.overspeedTolerance) km/h")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Stepper("", value: $settings.overspeedTolerance, in: 0...20)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Loại cảnh báo")
                        .font(.system(size: 12, weight: .medium))
                    kindChips(AlertKind.cameraKinds)
                    kindChips(AlertKind.speedKinds)
                    kindChips(AlertKind.otherKinds)
                }

                Button {
                    showAlertsManager = true
                } label: {
                    HStack {
                        Label("Quản lý dữ liệu cảnh báo", systemImage: "externaldrive.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(model.alertDatabase.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.subtleFill)
                    )
                }
                .buttonStyle(.plain)

                Text("Giới hạn tốc độ lấy theo biển báo/vùng đã nhập, dữ liệu OpenStreetMap, "
                     + "sau đó mới tới bảng mặc định của Thông tư 38/2024/TT-BGTVT. "
                     + "Cảnh báo chỉ để tham khảo — luôn tuân theo biển báo tại chỗ.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kindChips(_ kinds: [AlertKind]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(kinds) { kind in
                    AlertKindChip(kind: kind, isOn: settings.alertKinds.contains(kind)) {
                        settings.toggleAlertKind(kind)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        SectionCard(title: "Bản đồ", symbol: "map") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Kiểu bản đồ", selection: $settings.mapTypeIndex) {
                    Text("Tiêu chuẩn").tag(0)
                    Text("Vệ tinh lai").tag(1)
                    Text("Vệ tinh").tag(2)
                    Text("Tối giản").tag(3)
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $settings.showTraffic) {
                    Label("Hiện mật độ giao thông", systemImage: "car.2.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: $settings.showPOIs) {
                    Label("Hiện địa điểm của Apple Maps", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Divider()

                Toggle(isOn: $settings.navigationPitch3D) {
                    Label("Bản đồ 3D khi dẫn đường", systemImage: "view.3d")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: $settings.followUserInNavigation) {
                    Label("Tự bám theo vị trí khi bắt đầu", systemImage: "location.north.line.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Text("Khi dẫn đường, bản đồ tự xoay theo hướng đi và phóng to/thu nhỏ theo tốc độ "
                     + "(3D nghiêng 55°, hoặc 2D nhìn từ trên xuống). Kéo bản đồ để xem trước, "
                     + "bấm nút mũi tên để bám lại.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Data

    private var dataCard: some View {
        SectionCard(title: "Dữ liệu", symbol: "externaldrive.fill") {
            VStack(spacing: 8) {
                Button {
                    model.clearHistory()
                } label: {
                    HStack {
                        Label("Xoá lịch sử tìm kiếm", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(model.recents.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.subtleFill)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    model.clearFavorites()
                } label: {
                    HStack {
                        Label("Xoá địa điểm yêu thích", systemImage: "star.slash")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(model.favorites.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.subtleFill)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        SectionCard(title: "Về ứng dụng", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Phiên bản", "\(AppInfo.current.version) (\(AppInfo.current.build))")
                infoRow("Bundle ID", AppInfo.current.bundleIdentifier)
                infoRow("Commit", AppInfo.current.commit)
                infoRow("Bản đồ", "Apple Maps (MapKit)")
                infoRow("Xe máy", "Apple Maps + chấm điểm nội bộ")
                infoRow("Cảnh báo", "\(model.alertDatabase.count) điểm")
                infoRow("Dẫn đường", settings.navigationPitch3D ? "3D xoay theo hướng" : "2D")

                Text("Bản IPA này không có chữ ký Apple: dùng TrollStore (iOS ≤ 17.0) "
                     + "hoặc ký lại bằng Apple ID miễn phí (Sideloadly/SideStore) để cài.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Field

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.subtleFill)
                )
        }
    }


}
