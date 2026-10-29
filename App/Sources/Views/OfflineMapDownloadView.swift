import SwiftUI

@MainActor
struct OfflineMapDownloadView: View {
    @ObservedObject var store: OfflineMapStore
    var onUseAppleMaps: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("vietmap.osm.manifestURL") private var source = ""
    @AppStorage("vietmap.osm.wifiOnly") private var wifiOnly = true
    @State private var confirmsRemoval = false
    @State private var didCheckDefaultSource = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Bản đồ OpenStreetMap Việt Nam", systemImage: "map.fill")
                        .font(.headline)
                    Text(store.isReady
                         ? "Dữ liệu đã lưu trên iPhone. Bản đồ nền OSM không cần mạng khi sử dụng."
                         : "Chưa có dữ liệu trên máy. Hãy tải gói Việt Nam trước khi sử dụng OpenStreetMap. Apple Maps vẫn dùng được nếu bỏ qua.")
                    Text(store.status).font(.subheadline).foregroundStyle(.secondary)
                    if store.isBusy {
                        ProgressView(value: store.progress)
                        Button("Huỷ thao tác", role: .cancel) { store.cancel() }
                    }
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
                Section("Nguồn gói Việt Nam") {
                    TextField("URL HTTPS của manifest.json", text: $source)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(store.isBusy)
                    if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Chưa cấu hình máy chủ tải bản đồ. Cần gói PNG MBTiles Việt Nam đã được phép phân phối offline; không dùng URL tile công cộng của OSM.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("Kiểm tra gói tải") { store.checkSource(source) }
                        .disabled(store.isBusy || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Toggle("Chỉ tải qua Wi-Fi", isOn: $wifiOnly).disabled(store.isBusy)
                }
                if let manifest = store.offeredManifest {
                    Section("Xác nhận trước khi tải") {
                        LabeledContent("Khu vực", value: "Việt Nam (VN)")
                        LabeledContent("Phiên bản", value: manifest.version)
                        LabeledContent("Dung lượng", value: ByteCountFormatter.string(fromByteCount: manifest.byteCount, countStyle: .file))
                        LabeledContent("Mức zoom", value: "\(manifest.minZoom)–\(manifest.maxZoom)")
                        Text(manifest.attribution).font(.caption)
                        Text("VietMap Basic hiển thị đường sá, sông hồ và tên địa điểm cơ bản; chưa có đầy đủ POI/địa chỉ và không có bộ tính tuyến offline.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(store.isReady ? "Tải và thay thế gói Việt Nam" : "Tải bản đồ Việt Nam về máy") {
                            store.download(allowsCellular: !wifiOnly)
                        }
                        .disabled(store.isBusy)
                        Text("Cần dung lượng trống bằng gói tải + 128 MB. Khi cập nhật, giữ bản cũ đến khi bản mới vượt qua kiểm tra SHA-256. Giữ app mở trong lúc tải; nếu bị ngắt, có thể thử tải lại.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let database = store.database {
                    Section("Đang lưu trên thiết bị") {
                        LabeledContent("Phiên bản", value: database.manifest.version)
                        LabeledContent("Dung lượng", value: ByteCountFormatter.string(fromByteCount: database.manifest.byteCount, countStyle: .file))
                        Text(database.manifest.attribution).font(.caption)
                        Button("Xoá gói bản đồ Việt Nam", role: .destructive) { confirmsRemoval = true }
                            .disabled(store.isBusy)
                    }
                }
                Section {
                    Link("© OpenStreetMap contributors", destination: OpenStreetMapOverlay.copyrightURL)
                    Text("Gói dữ liệu chỉ dành cho khu vực Việt Nam, không phải bản đồ toàn thế giới. Ngoài vùng gói sẽ không có tile. Phóng to vượt mức zoom gốc chỉ phóng ảnh, không bổ sung chi tiết. Tìm địa điểm và tính tuyến vẫn dùng Apple Maps và có thể cần Internet. Cảnh báo VietHUD không phụ thuộc gói này.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let onUseAppleMaps {
                        Button("Dùng Apple Maps") { onUseAppleMaps(); dismiss() }
                    }
                }
            }
            .navigationTitle("Bản đồ Việt Nam offline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
            .confirmationDialog("Xoá bản đồ đã tải? Lần dùng OSM sau sẽ cần tải lại.", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Xoá bản đồ", role: .destructive) { store.remove() }
            }
            .onAppear {
                if source.isEmpty, let bundled = Bundle.main.object(forInfoDictionaryKey: "VNOfflineMapManifestURL") as? String,
                   !bundled.hasPrefix("$(") { source = bundled }
            }
            .onChange(of: source) { _ in store.clearOffer() }
            .task {
                await store.restore()
                if !store.isReady, !didCheckDefaultSource, !source.isEmpty {
                    didCheckDefaultSource = true
                    store.checkSource(source)
                }
            }
        }
    }
}
