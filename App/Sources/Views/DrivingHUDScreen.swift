import SwiftUI
import UIKit
import Combine

/// HUD độc lập: GPS/cảnh báo offline, không phụ thuộc việc đang có tuyến MapKit.
@MainActor
struct DrivingHUDScreen: View {
    @ObservedObject var location: LocationService
    @ObservedObject var controller: SpeedmapController
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: VoiceGuide
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("vietmap.hud.mirrored") private var mirrored = false
    @AppStorage("vietmap.hud.keepAwake") private var keepAwake = true
    @State private var overspeed = OverspeedMonitor()
    @State private var previousIdleTimerDisabled = false
    @State private var showsOptions = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let cyan = Color(red: 0.36, green: 0.92, blue: 0.87)

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let fresh = HUDSafety.hasUsableFix(location.lastLocation, now: context.date)
                    && location.isAuthorized && scenePhase == .active
                let speed = fresh ? HUDSafety.speedKmh(location.lastLocation, now: context.date) : nil
                let limit = fresh ? controller.speedLimitKmh : nil
                let landscape = geometry.size.width > geometry.size.height
                VStack(spacing: 12) {
                    header(fresh: fresh)
                    Group {
                        if landscape {
                            HStack(spacing: 24) {
                                speedometer(speed: speed, limit: limit)
                                    .frame(maxWidth: .infinity)
                                roadAndAlerts(fresh: fresh, limit: limit)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            speedometer(speed: speed, limit: limit)
                                .frame(maxHeight: .infinity)
                            roadAndAlerts(fresh: fresh, limit: limit)
                        }
                    }
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    footer
                }
                .padding(landscape ? 16 : 22)
            }
        }
        .background(Color(red: 0.025, green: 0.04, blue: 0.06).ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsOptions) { options }
        .onAppear {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            updateIdleTimer()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
        .onChange(of: settings.voiceGuidance) { enabled in
            if !enabled { voice.stop() }
        }
        .onChange(of: keepAwake) { _ in updateIdleTimer() }
        .onChange(of: scenePhase) { _ in updateIdleTimer() }
        .onReceive(clock) { now in
            let usable = scenePhase == .active && location.isAuthorized
                && HUDSafety.hasUsableFix(location.lastLocation, now: now)
            let speed = usable ? HUDSafety.speedKmh(location.lastLocation, now: now) : nil
            let announce = overspeed.update(speedKmh: speed,
                                            limitKmh: usable ? controller.speedLimitKmh : nil,
                                            now: now)
            if announce {
                if settings.alertBeep { AlertSound.beep() }
                if settings.voiceGuidance { voice.speak("Bạn đang vượt giới hạn tốc độ. Hãy giảm tốc.") }
            }
        }
    }

    private func header(fresh: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("VIETMAP / HUD")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                Text("CẢNH BÁO GIAO THÔNG OFFLINE")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
            }
            Spacer()
            Label(fresh ? "GPS tốt" : "Chờ GPS", systemImage: fresh ? "location.fill" : "location.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(fresh ? cyan : .orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func speedometer(speed: Double?, limit: Int?) -> some View {
        let speeding = speed.map { value in limit.map { value > Double($0) + 2 } ?? false } ?? false
        return VStack(spacing: 0) {
            Text(speed.map { String(Int($0.rounded())) } ?? "—")
                .font(.system(size: 132, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(speeding ? Color.red : cyan)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(speed.map { "Tốc độ \(Int($0.rounded())) ki lô mét trên giờ" } ?? "Chưa có tốc độ GPS")
            Text("KM/H").font(.system(size: 14, weight: .semibold, design: .monospaced))
                .tracking(5).foregroundStyle(.gray)
            Text(speeding ? "VƯỢT GIỚI HẠN · GIẢM TỐC" : "LÁI XE AN TOÀN")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(speeding ? Color.red : .gray)
                .padding(.top, 12)
        }
    }

    private func roadAndAlerts(fresh: Bool, limit: Int?) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                if let limit {
                    SpeedLimitSign(limitKmh: limit, diameter: 64)
                } else {
                    Text("—").font(.system(size: 28, weight: .bold))
                        .frame(width: 64, height: 64)
                        .overlay(Circle().stroke(Color.gray, lineWidth: 4))
                        .accessibilityLabel("Chưa xác định giới hạn tốc độ")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("GIỚI HẠN TỐC ĐỘ")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
                    Text(fresh ? (controller.road?.name ?? "Chưa khớp được đường") : "Không có vị trí tin cậy")
                        .font(.system(size: 16, weight: .semibold)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))

            if !location.isAuthorized || !fresh || !controller.isReady {
                statusMessage(fresh: fresh)
            } else if controller.alerts.isEmpty {
                Label("Không có cảnh báo trong phạm vi quét", systemImage: "checkmark.shield")
                    .font(.system(size: 13)).foregroundStyle(cyan)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            } else {
                // Một thẻ chính giúp màn hình ngang vẫn đủ chỗ và dễ đọc khi lái xe.
                ForEach(Array(controller.alerts.prefix(1))) { alert in
                    HStack(spacing: 12) {
                        Image(systemName: alert.kind == .camera ? "video.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title).font(.system(size: 16, weight: .bold)).lineLimit(2)
                            if let subtitle = alert.subtitle {
                                Text(subtitle).font(.caption).foregroundStyle(.gray).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("\(Int(alert.distanceM.rounded())) m")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.orange)
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func statusMessage(fresh: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if location.isDenied {
                Text("Cần quyền vị trí chính xác")
                Button("Mở Cài đặt iOS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } else if !fresh {
                Text("Đang chờ GPS chính xác. Hãy đặt máy ở nơi thoáng.")
            } else if let error = controller.loadError {
                Text("Không nạp được dữ liệu: \(error)")
            } else {
                Text("Đang nạp dữ liệu cảnh báo offline…")
            }
        }
        .font(.system(size: 13)).foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }

    private var footer: some View {
        HStack {
            Button { dismiss() } label: { Label("Bản đồ", systemImage: "map") }
            Spacer()
            Button { settings.voiceGuidance.toggle() } label: {
                Image(systemName: settings.voiceGuidance ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .accessibilityLabel(settings.voiceGuidance ? "Tắt giọng nói" : "Bật giọng nói")
            Spacer()
            Button { showsOptions = true } label: { Label("Tùy chọn", systemImage: "slider.horizontal.3") }
        }
        .font(.system(size: 14, weight: .semibold))
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private var options: some View {
        NavigationStack {
            Form {
                Section("Hiển thị HUD") {
                    Toggle("Phản chiếu lên kính", isOn: $mirrored)
                    Toggle("Giữ sáng màn hình", isOn: $keepAwake)
                    Toggle("Giọng nói tiếng Việt", isOn: $settings.voiceGuidance)
                    Toggle("Âm báo cảnh báo", isOn: $settings.alertBeep)
                }
                Section("Dữ liệu") {
                    LabeledContent("Nguồn", value: "VietHUD / Speedmap")
                    LabeledContent("Phiên bản", value: controller.metadata?.mapVersion ?? "Chưa nạp")
                    Text("\(controller.metadata?.attribution ?? "Xem nguồn dữ liệu VietHUD trước khi phân phối lại.")")
                        .font(.caption)
                }
                Section("Lưu ý an toàn") {
                    Text("Chỉ hỗ trợ khi ứng dụng đang mở. HUD không thay thế biển báo thực tế. Không có cảnh báo không có nghĩa là không có camera. Bản đồ và tính tuyến Apple Maps có thể cần mạng.")
                    Text("Tải giọng Tiếng Việt trong Cài đặt iOS trước chuyến đi để đọc cảnh báo khi không có mạng. Phản chiếu phụ thuộc kính và ánh sáng; chỉ điều chỉnh khi đã dừng xe.")
                }
            }
            .navigationTitle("Tùy chọn HUD")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { showsOptions = false } } }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && keepAwake
            ? true : previousIdleTimerDisabled
    }
}
