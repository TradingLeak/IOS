import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

/// Danh sách cảnh báo: trên tuyến đang chọn, quanh vị trí hiện tại, và quản lý dữ liệu.
@MainActor
struct AlertsSheet: View {
    @ObservedObject var model: MapViewModel
    @ObservedObject var settings: AppSettings

    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0
    @State private var importerPresented = false
    @State private var message: String?
    @State private var shareItem: ShareItem?
    @State private var isDownloading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    picker

                    if let message {
                        InfoBanner(kind: .info, text: message)
                    }

                    switch tab {
                    case 0: onRouteSection
                    case 1: nearbySection
                    default: dataSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Cảnh báo giao thông")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importerPresented,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Tổng quan

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.alertGradient))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bộ dữ liệu cảnh báo")
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.alertDataSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                StatTile(value: "\(model.routeAlerts.count)", label: "trên tuyến", symbol: "map", tint: AppTheme.accent)
                StatTile(value: "\(model.alertDatabase.cameraCount)", label: "camera", symbol: "camera.fill", tint: AppTheme.danger)
                StatTile(value: "\(model.importedAlertCount)", label: "nhập thêm", symbol: "square.and.arrow.down", tint: AppTheme.success)
            }

            if model.routeAlerts.isEmpty, model.hasRoute {
                Text("Tuyến hiện tại chưa đi qua cảnh báo nào trong bộ dữ liệu.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if !model.hasRoute {
                Text("Chọn tuyến đường để xem cảnh báo dọc đường.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    private var picker: some View {
        Picker("Loại dữ liệu", selection: $tab) {
            Text("Trên tuyến").tag(0)
            Text("Quanh bạn").tag(1)
            Text("Dữ liệu").tag(2)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Trên tuyến

    @ViewBuilder
    private var onRouteSection: some View {
        if model.routeAlerts.isEmpty {
            SectionCard(title: "Trên tuyến", symbol: "map") {
                EmptyHint(symbol: "checkmark.shield",
                          title: "Không có cảnh báo trên tuyến",
                          message: "Thử tải biển tốc độ từ OpenStreetMap ở tab Dữ liệu để có thêm dữ liệu.")
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CẢNH BÁO TRÊN TUYẾN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.routeAlerts.count) điểm")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(model.routeAlerts.prefix(40))) { active in
                    AlertRow(active: active, showsImage: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .floatingCard()
        }
    }

    // MARK: - Quanh bạn

    private var nearbySection: some View {
        VStack(spacing: 12) {
            Button {
                model.loadNearbyAlerts()
                message = model.alertStatusMessage
            } label: {
                Label("Tìm cảnh báo quanh vị trí của tôi", systemImage: "location.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .primaryGradientBackground(cornerRadius: 14)
            }
            .buttonStyle(.plain)

            if nearbyActive.isEmpty {
                SectionCard(title: "Quanh bạn", symbol: "location.circle") {
                    EmptyHint(symbol: "camera.metering.unknown",
                              title: "Chưa có dữ liệu quanh đây",
                              message: "Bấm nút phía trên để tìm trong bán kính 3,5 km.")
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(nearbyActive.prefix(40))) { active in
                        AlertRow(active: active, showsImage: true)
                    }
                }
                .padding(14)
                .floatingCard()
            }
        }
    }

    private var nearbyActive: [ActiveAlert] {
        let origin = model.location.coordinate ?? model.selectedPreset.coordinate
        let center = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let mapped = model.nearbyAlertPoints.map { alert in
            ActiveAlert(alert: alert,
                        distance: center.distance(from: alert.location),
                        warnDistance: 400,
                        distanceAlongRoute: 0)
        }
        return mapped.sorted { $0.distance < $1.distance }
    }

    // MARK: - Dữ liệu

    private var dataSection: some View {
        VStack(spacing: 14) {
            SectionCard(title: "Nhập / xuất", symbol: "arrow.up.arrow.down.circle") {
                VStack(spacing: 8) {
                    Button {
                        importerPresented = true
                    } label: {
                        row(icon: "square.and.arrow.down", tint: AppTheme.accent,
                            title: "Nhập JSON cảnh báo",
                            detail: "Tệp do bạn hoặc cộng đồng tạo (xem docs/ALERTS.md)")
                    }
                    .buttonStyle(.plain)

                    Button {
                        do {
                            shareItem = ShareItem(url: try model.exportAlerts())
                        } catch {
                            message = "Không xuất được tệp: \(error.localizedDescription)"
                        }
                    } label: {
                        row(icon: "square.and.arrow.up", tint: AppTheme.success,
                            title: "Xuất toàn bộ dữ liệu (JSON)",
                            detail: "Chia sẻ qua AirDrop / Files để dùng cho app khác")
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            isDownloading = true
                            await model.downloadOSMAlerts()
                            isDownloading = false
                            message = model.alertStatusMessage
                        }
                    } label: {
                        HStack {
                            row(icon: "globe.asia.australia.fill", tint: AppTheme.warning,
                                title: "Tải biển tốc độ từ OpenStreetMap",
                                detail: "Chỉ tải quanh tuyến đang chọn (© OSM contributors, ODbL)")
                            if isDownloading {
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.clearImportedAlerts()
                        message = model.alertStatusMessage
                    } label: {
                        row(icon: "trash", tint: AppTheme.danger,
                            title: "Xoá dữ liệu đã nhập",
                            detail: "Giữ nguyên bộ dữ liệu có sẵn trong app")
                    }
                    .buttonStyle(.plain)
                }
            }

            SectionCard(title: "Nguồn dữ liệu", symbol: "doc.text.magnifyingglass") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.alertSources) { source in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.system(size: 13, weight: .semibold))
                            if let note = source.note {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            if let license = source.license {
                                Text(license)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if let updated = model.alertDatabase.generatedAt {
                        Text("Cập nhật dữ liệu: \(updated.prefix(10))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Text("Dữ liệu chỉ để tham khảo. Luôn tuân theo biển báo và hiệu lệnh của CSGT tại chỗ.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.subtleFill)
        )
    }

    // MARK: - Nhập tệp

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                message = try model.importAlerts(from: data)
            } catch {
                message = "Không đọc được tệp: \(error.localizedDescription)"
            }
        case .failure(let error):
            message = "Không chọn được tệp: \(error.localizedDescription)"
        }
    }
}
