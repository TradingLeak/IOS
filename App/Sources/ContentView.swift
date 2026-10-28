import SwiftUI
import UIKit

struct ContentView: View {
    private let info = BuildInfo.current

    var body: some View {
        NavigationView {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section("Thông tin app") {
                    row("Tên hiển thị", info.displayName, "app.badge")
                    row("Bundle ID", info.bundleIdentifier, "number")
                    row("Phiên bản", "\(info.version) (\(info.buildNumber))", "tag")
                    row("iOS tối thiểu", info.minimumOS, "iphone")
                    row("Kiến trúc", info.architecture, "cpu")
                }

                Section("Bản build") {
                    row("Thời điểm build", info.buildDate, "calendar")
                    row("Git commit", info.gitCommit, "hammer.fill")
                    row("Chữ ký", info.isSigned ? "Đã ký" : "Chưa ký (unsigned)", info.isSigned ? "checkmark.seal.fill" : "xmark.seal.fill")
                }

                Section("Thiết bị") {
                    row("Model", deviceModel, "iphone")
                    row("Hệ điều hành", "iOS \(UIDevice.current.systemVersion)", "gear")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = changelog
                    } label: {
                        Label("Copy thông tin build", systemImage: "doc.on.doc")
                    }
                }

                Section {
                    Text("Bản IPA này được build với CODE_SIGNING_ALLOWED=NO nên không có chữ ký Apple. "
                         + "Máy thường sẽ cần ký lại bằng Apple ID miễn phí (Sideloadly / AltStore), "
                         + "hoặc cài trực tiếp nếu máy dùng TrollStore / jailbreak.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hello IPA")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 92, height: 92)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.24, green: 0.45, blue: 0.99),
                                 Color(red: 0.58, green: 0.28, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(info.displayName)
                .font(.title2.weight(.semibold))

            Text(info.isSigned ? "IPA đã ký" : "IPA không ký · unsigned")
                .font(.caption.weight(.semibold))
                .foregroundColor(info.isSigned ? .green : .orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        (info.isSigned ? Color.green : Color.orange).opacity(0.14)
                    )
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundColor(.accentColor)
                .frame(width: 22)
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { rawBuffer -> String in
            let bytes = rawBuffer.prefix(while: { $0 != 0 })
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone / iPad" : machine
    }

    private var changelog: String {
        """
        \(info.displayName) \(info.version) (\(info.buildNumber))
        Bundle ID: \(info.bundleIdentifier)
        Build: \(info.buildDate) · \(info.gitCommit)
        iOS tối thiểu: \(info.minimumOS) · \(info.architecture)
        Chữ ký: \(info.isSigned ? "đã ký" : "unsigned")
        """
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
