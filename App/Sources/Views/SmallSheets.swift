import SwiftUI

struct FavoritesSheet: View {
    let favorites: [Place]
    let recents: [Place]
    let onSelect: (Place) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if favorites.isEmpty {
                        EmptyHint(symbol: "star",
                                  title: "Chưa có địa điểm yêu thích",
                                  message: "Mở chỉ đường rồi bấm ngôi sao để lưu địa điểm.")
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(favorites) { place in
                            Button {
                                onSelect(place)
                            } label: {
                                row(place, symbol: "star.fill", tint: AppTheme.warning)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Yêu thích")
                }

                Section {
                    if recents.isEmpty {
                        EmptyHint(symbol: "clock",
                                  title: "Chưa có lịch sử",
                                  message: "Các địa điểm bạn tìm kiếm sẽ xuất hiện ở đây.")
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(recents) { place in
                            Button {
                                onSelect(place)
                            } label: {
                                row(place, symbol: "clock.arrow.circlepath", tint: .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Tìm gần đây")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Địa điểm đã lưu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ place: Place, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(place.displaySubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct CityPickerSheet: View {
    let selected: MapPreset
    let onSelect: (MapPreset) -> Void

    @Environment(\.dismiss) private var dismiss

    private var presets: [MapPreset] {
        [MapPreset.vietnam] + MapPreset.cities
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(presets) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: preset.id == "vn" ? "flag.fill" : "building.2.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(preset.id == selected.id ? Color.white : AppTheme.accent)
                                    Spacer()
                                    if preset.id == selected.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text(preset.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(preset.id == selected.id ? Color.white : Color.primary)
                                    .lineLimit(1)
                                Text(String(format: "%.2f, %.2f", preset.latitude, preset.longitude))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(preset.id == selected.id ? Color.white.opacity(0.85) : Color.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(preset.id == selected.id
                                          ? AnyShapeStyle(AppTheme.accentGradient)
                                          : AnyShapeStyle(AppTheme.card))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.cardStroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Chọn khu vực")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
