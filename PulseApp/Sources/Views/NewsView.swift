import SwiftUI

struct NewsView: View {
    @EnvironmentObject var store: PulseStore
    @State private var selected: NewsItem?
    @State private var showSettings = false

    private var categories: [NewsCategory] {
        NewsCategory.allCases.filter { category in
            store.news.contains { $0.category == category }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            PulseFilterChip(title: "Tất cả",
                                            isSelected: store.newsCategory == nil,
                                            tint: PulseTheme.violet) {
                                store.newsCategory = nil
                            }
                            ForEach(categories) { category in
                                PulseFilterChip(title: category.title,
                                                isSelected: store.newsCategory == category,
                                                tint: category.tint) {
                                    store.newsCategory = store.newsCategory == category ? nil : category
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(PulseTheme.textTertiary)
                        TextField("Tìm kiếm tin, mã, ngân hàng…", text: $store.newsQuery)
                            .foregroundStyle(PulseTheme.textPrimary)
                        if !store.newsQuery.isEmpty {
                            Button {
                                store.newsQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(PulseTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .pulseField()

                    content
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(PulseTheme.background)
            .navigationTitle("Tin tức")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.loadNews(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(PulseTheme.teal)
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(PulseTheme.textSecondary)
                    }
                }
            }
            .sheet(item: $selected) { item in
                NewsDetailView(item: item)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .refreshable { await store.loadNews(force: true) }
        }
    }

    // MARK: - Nội dung

    @ViewBuilder
    private var content: some View {
        if store.isLoadingNews && store.news.isEmpty {
            PulseLoading(title: "Đang tải tin tức")
        } else if let error = store.newsError, store.news.isEmpty {
            PulseErrorState(message: error) {
                Task { await store.loadNews(force: true) }
            }
        } else if store.visibleNews.isEmpty {
            PulseEmptyState(symbol: "newspaper",
                            title: store.newsQuery.isEmpty ? "Không có tin trong mục này" : "Không tìm thấy tin phù hợp",
                            message: "Thử đổi từ khoá hoặc nguồn tin trong Cài đặt.")
        } else {
            LazyVStack(spacing: 8) {
                ForEach(store.visibleNews) { item in
                    Button {
                        selected = item
                    } label: {
                        NewsRowView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Tổng hợp từ " + NewsSources.enabledFeeds().map(\.title).joined(separator: ", ") +
                 " · nhấn vào tin để đọc bản đầy đủ")
                .font(.system(size: 10))
                .foregroundStyle(PulseTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }
}

// MARK: - Chi tiết tin

struct NewsDetailView: View {
    let item: NewsItem
    @Environment(\.dismiss) private var dismiss
    @State private var showSafari = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text(item.source)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(item.category.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(item.category.tint.opacity(0.14)))
                        Text(item.category.title)
                            .font(.system(size: 11))
                            .foregroundStyle(PulseTheme.textTertiary)
                        Spacer()
                        if let date = item.date {
                            Text(PulseFormat.relativeTime(date))
                                .font(.system(size: 11))
                                .foregroundStyle(PulseTheme.textTertiary)
                        }
                    }

                    Text(item.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PulseTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let date = item.date {
                        Text(Fmt.dateTime(date))
                            .font(.system(size: 12))
                            .foregroundStyle(PulseTheme.textSecondary)
                    }

                    Divider().overlay(PulseTheme.stroke)

                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 15))
                            .foregroundStyle(PulseTheme.textSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Nguồn này chỉ cung cấp tiêu đề. Mở trang gốc để đọc toàn bộ bài viết.")
                            .font(.system(size: 14))
                            .foregroundStyle(PulseTheme.textSecondary)
                    }

                    PulsePrimaryButton(title: "Đọc bản đầy đủ", symbol: "safari.fill", tint: item.category.tint) {
                        showSafari = true
                    }

                    if let url = URL(string: item.link) {
                        ShareLink(item: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                                Text("Chia sẻ").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(PulseTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .background(PulseTheme.background)
            .navigationTitle("Tin tức")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                        .foregroundStyle(PulseTheme.teal)
                }
            }
            .sheet(isPresented: $showSafari) {
                if let url = URL(string: item.link) {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
