import Foundation
import Combine

@MainActor
final class OfflineMapStore: ObservableObject {
    static let shared = OfflineMapStore()
    @Published private(set) var database: OfflineMBTiles?
    @Published private(set) var offeredManifest: OfflineMapManifest?
    @Published private(set) var isBusy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = "Chưa tải bản đồ Việt Nam"
    @Published private(set) var errorMessage: String?
    var isReady: Bool { database != nil }

    private let directory: URL
    private var operation: Task<Void, Never>?
    private var didRestore = false

    private struct Receipt: Codable {
        let fileName: String
        let manifest: OfflineMapManifest
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VietnamOfflineMap", isDirectory: true)
    }

    private var receiptURL: URL { directory.appendingPathComponent("installed.json") }

    /// Không chỉ dùng một cờ UserDefaults: kiểm tra file thật và metadata sau mỗi lần mở app.
    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            cleanUnusedFiles(keeping: nil)
            return
        }
        isBusy = true
        status = "Đang kiểm tra bản đồ đã lưu…"
        defer { isBusy = false }
        do {
            let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL))
            guard UUID(uuidString: String(receipt.fileName.dropLast(".mbtiles".count))) != nil,
                  receipt.fileName.hasSuffix(".mbtiles") else { throw OfflineMapError.invalidManifest }
            let url = directory.appendingPathComponent(receipt.fileName)
            let manifest = receipt.manifest
            database = try await Task.detached(priority: .userInitiated) {
                let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
                guard size?.int64Value == manifest.byteCount else { throw OfflineMapError.size }
                return try OfflineMBTiles(url: url, manifest: manifest)
            }.value
            status = "Đã có bản đồ Việt Nam · \(manifest.version)"
            cleanUnusedFiles(keeping: receipt.fileName)
        } catch {
            errorMessage = "Bản đồ lưu trên máy bị thiếu hoặc không đọc được. \(error.localizedDescription)"
            status = "Cần tải lại bản đồ Việt Nam"
        }
    }

    func clearOffer() {
        guard !isBusy else { return }
        offeredManifest = nil
        errorMessage = nil
    }

    /// Bước 1: đọc manifest nhỏ, hiển thị dung lượng trước khi người dùng xác nhận tải.
    func checkSource(_ text: String) {
        guard !isBusy else { return }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              OfflineMapManifest.isDownloadURL(url) else {
            errorMessage = "Nhập URL HTTPS của manifest gói Việt Nam, không phải URL tile OSM."
            return
        }
        offeredManifest = nil
        errorMessage = nil
        isBusy = true
        status = "Đang lấy thông tin gói Việt Nam…"
        operation = Task {
            defer { isBusy = false; operation = nil }
            do {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      data.count <= 1_048_576, let finalURL = http.url,
                      OfflineMapManifest.isDownloadURL(finalURL) else { throw OfflineMapError.network }
                try Task.checkCancellation()
                let manifest = try JSONDecoder().decode(OfflineMapManifest.self, from: data)
                try manifest.validate()
                offeredManifest = manifest
                status = "Sẵn sàng tải gói Việt Nam"
            } catch { record(error) }
        }
    }

    /// Bước 2: tải một file MBTiles được phép phân phối offline, không tải từng tile công cộng.
    func download(allowsCellular: Bool) {
        guard !isBusy, let manifest = offeredManifest else { return }
        isBusy = true
        progress = 0
        errorMessage = nil
        status = "Đang tải bản đồ Việt Nam…"
        operation = Task {
            var stagedURL: URL?
            defer {
                if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
                isBusy = false
                operation = nil
            }
            do {
                try manifest.validate()
                try prepareDirectory()
                let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                let available = values.volumeAvailableCapacityForImportantUsage ?? 0
                // File cũ vẫn còn trong lúc cập nhật; tải bằng file tạm, không nhân đôi trong RAM.
                guard available >= manifest.byteCount + 128 * 1024 * 1024 else { throw OfflineMapError.noSpace }
                let config = URLSessionConfiguration.default
                config.allowsCellularAccess = allowsCellular
                config.allowsExpensiveNetworkAccess = allowsCellular
                config.timeoutIntervalForRequest = 60
                config.timeoutIntervalForResource = 24 * 60 * 60
                let session = URLSession(configuration: config)
                defer { session.invalidateAndCancel() }
                let delegate = MapDownloadProgress(expectedBytes: manifest.byteCount) { [weak self] received in
                    Task { @MainActor in
                        guard let self, self.isBusy else { return }
                        self.progress = min(Double(received) / Double(manifest.byteCount), 1)
                    }
                }
                let (temporary, response) = try await session.download(from: manifest.downloadURL, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let finalURL = http.url, OfflineMapManifest.isDownloadURL(finalURL) else { throw OfflineMapError.network }
                try Task.checkCancellation()
                let fileName = UUID().uuidString + ".mbtiles"
                let destination = directory.appendingPathComponent(fileName)
                stagedURL = destination
                try FileManager.default.moveItem(at: temporary, to: destination)
                status = "Đang xác minh SHA-256 và dữ liệu…"
                let verification = Task.detached(priority: .userInitiated) {
                    try OfflineMBTiles.verifyFile(destination, manifest: manifest)
                    try Task.checkCancellation()
                    return try OfflineMBTiles(url: destination, manifest: manifest)
                }
                let verified = try await withTaskCancellationHandler(operation: {
                    try await verification.value
                }, onCancel: { verification.cancel() })
                try Task.checkCancellation()
                // Receipt được thay nguyên tử SAU khi file đã tải và xác minh xong.
                // Mất điện trước bước này: bản cũ vẫn có hiệu lực.
                let receipt = Receipt(fileName: fileName, manifest: manifest)
                try JSONEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
                database = verified
                stagedURL = nil
                progress = 1
                status = "Đã có bản đồ Việt Nam · \(manifest.version)"
                cleanUnusedFiles(keeping: fileName)
            } catch { record(error) }
        }
    }

    func cancel() { operation?.cancel() }

    func remove() {
        guard !isBusy else { return }
        do {
            // Xoá receipt trước: lần mở sau sẽ không nhận file dở là bản đồ đã cài.
            if FileManager.default.fileExists(atPath: receiptURL.path) {
                try FileManager.default.removeItem(at: receiptURL)
            }
            database = nil
            cleanUnusedFiles(keeping: nil)
            status = "Chưa tải bản đồ Việt Nam"
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func cleanUnusedFiles(keeping name: String?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "mbtiles" && file.lastPathComponent != name {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func record(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            errorMessage = nil
            status = isReady ? "Giữ bản đồ Việt Nam đã có" : "Đã huỷ tải. Có thể thử lại."
        } else {
            errorMessage = error.localizedDescription
            status = isReady ? "Cập nhật thất bại, vẫn dùng bản đồ cũ" : "Chưa cài được bản đồ Việt Nam"
        }
    }
}

private final class MapDownloadProgress: NSObject, URLSessionDownloadDelegate {
    private let expectedBytes: Int64
    private let progress: (Int64) -> Void
    private var lastReport: TimeInterval = 0
    init(expectedBytes: Int64, progress: @escaping (Int64) -> Void) {
        self.expectedBytes = expectedBytes
        self.progress = progress
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedBytes { downloadTask.cancel(); return }
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastReport >= 0.2 || totalBytesWritten == expectedBytes {
            lastReport = now
            progress(totalBytesWritten)
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { OfflineMapManifest.isDownloadURL($0) } == true ? request : nil)
    }
}
