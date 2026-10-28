import SwiftUI
import MapKit

struct SearchSheet: View {
    @ObservedObject var searchService: SearchService
    let title: String
    let currentPlace: Place?
    let recents: [Place]
    let favorites: [Place]
    let onSelect: (Place) -> Void
    let onUseCurrentLocation: () -> Place?

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                SearchField(text: $query,
                            placeholder: "Tên địa điểm, địa chỉ, quán ăn…",
                            onSubmit: { runSearch() },
                            onClear: {
                                results = []
                                searchService.clearSuggestions()
                            },
                            focus: $isFocused)
                    .padding(.horizontal, 16)

                if let errorText {
                    InfoBanner(kind: .error, text: errorText)
                        .padding(.horizontal, 16)
                }

                List {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emptyQueryContent
                    } else {
                        localMatchContent
                        suggestionContent
                        searchResultContent
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if isSearching {
                        ProgressView("Đang tìm…")
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.card)
                            )
                    }
                }
            }
            .padding(.top, 8)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .onAppear {
            isFocused = true
            searchService.clearSuggestions()
        }
        .onChange(of: query) { value in
            searchService.suggest(value)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var emptyQueryContent: some View {
        if let currentPlace {
            Section {
                Button {
                    onSelect(currentPlace)
                } label: {
                    row(title: "Vị trí của tôi",
                        subtitle: currentPlace.subtitle,
                        symbol: "location.fill",
                        tint: AppTheme.accent,
                        badge: "GPS")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Gợi ý")
            }
        }

        if !favorites.isEmpty {
            Section {
                ForEach(favorites) { place in
                    Button {
                        onSelect(place)
                    } label: {
                        row(title: place.name,
                            subtitle: place.displaySubtitle,
                            symbol: "star.fill",
                            tint: AppTheme.warning)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Yêu thích")
            }
        }

        if !recents.isEmpty {
            Section {
                ForEach(recents) { place in
                    Button {
                        onSelect(place)
                    } label: {
                        row(title: place.name,
                            subtitle: place.displaySubtitle,
                            symbol: "clock.arrow.circlepath",
                            tint: .secondary)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Tìm gần đây")
            }
        }

        if favorites.isEmpty && recents.isEmpty && currentPlace == nil {
            EmptyHint(symbol: "magnifyingglass",
                      title: "Nhập tên địa điểm",
                      message: "Ví dụ: “Hồ Hoàn Kiếm”, “Bến Thành”, “Đại học Bách khoa Hà Nội”.")
                .listRowSeparator(.hidden)
        }
    }

    /// Yêu thích / gần đây khớp câu tìm — tìm không dấu vẫn ra ("ho tay" → "Hồ Tây").
    @ViewBuilder
    private var localMatchContent: some View {
        let matches = SearchRanking.rank(SearchRanking.filter(favorites + recents, query: query),
                                         query: query,
                                         near: currentPlace?.coordinate)
        if !matches.isEmpty {
            Section {
                ForEach(matches.prefix(5)) { place in
                    Button {
                        onSelect(place)
                    } label: {
                        row(title: place.name,
                            subtitle: place.displaySubtitle,
                            symbol: favorites.contains(where: { $0.id == place.id }) ? "star.fill" : "clock.arrow.circlepath",
                            tint: favorites.contains(where: { $0.id == place.id }) ? AppTheme.warning : AppTheme.accentDeep,
                            badge: SearchRanking.distanceText(place, from: currentPlace?.coordinate))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Trong máy bạn")
            }
        }
    }

    @ViewBuilder
    private var suggestionContent: some View {
        if !searchService.suggestions.isEmpty {
            Section {
                ForEach(searchService.suggestions) { suggestion in
                    Button {
                        pick(suggestion)
                    } label: {
                        row(title: suggestion.title,
                            subtitle: suggestion.subtitle,
                            symbol: "mappin.and.ellipse",
                            tint: AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Gợi ý từ Apple Maps")
            }
        }
    }

    @ViewBuilder
    private var searchResultContent: some View {
        if !results.isEmpty {
            Section {
                ForEach(results) { place in
                    Button {
                        onSelect(place)
                    } label: {
                        row(title: place.name,
                            subtitle: place.displaySubtitle,
                            symbol: "mappin.circle.fill",
                            tint: AppTheme.success,
                            badge: SearchRanking.distanceText(place, from: currentPlace?.coordinate))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Kết quả tìm kiếm")
            }
        }
    }

    // MARK: - Row

    private func row(title: String, subtitle: String, symbol: String, tint: Color, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.14)))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func pick(_ suggestion: SearchSuggestion) {
        Task {
            isSearching = true
            defer { isSearching = false }
            do {
                if let place = try await searchService.resolve(suggestion) {
                    onSelect(place)
                } else {
                    errorText = "Không lấy được toạ độ của địa điểm này."
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        Task {
            isSearching = true
            errorText = nil
            do {
                let found = try await searchService.search(query: text)
                results = SearchRanking.rank(found, query: text, near: currentPlace?.coordinate)
                if results.isEmpty {
                    errorText = "Không tìm thấy địa điểm nào khớp với \"\(text)\"."
                }
            } catch {
                results = []
                errorText = error.localizedDescription
            }
            isSearching = false
        }
    }
}
