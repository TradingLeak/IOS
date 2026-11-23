import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var store: PulseStore
    @State private var showSettings = false

    private var majorCurrencies: [String] {
        let preferred = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "CNY", "NZD"]
        let available = Set(store.currencies)
        var list = preferred.filter { available.contains($0) }
        for code in store.currencies where !list.contains(code) && list.count < 12 {
            list.append(code)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let next = store.upcomingHighImpact.first {
                        nextEventCard(next)
                    }

                    filters

                    if store.isLoadingCalendar && store.events.isEmpty {
                        PulseLoading(title: "Đang tải lịch kinh tế")
                    } else if let error = store.calendarError, store.events.isEmpty {
                        PulseErrorState(message: error) {
                            Task { await store.loadCalendar(force: true) }
                        }
                    } else if store.calendarDays.isEmpty {
                        PulseEmptyState(symbol: "calendar.badge.exclamationmark",
                                        title: "Không có sự kiện phù hợp bộ lọc",
                                        message: "Đổi mức ảnh hưởng hoặc tiền tệ, hoặc tải lại lịch.")
                    } else {
                        ForEach(store.calendarDays) { day in
                            daySection(day)
                        }
                        Text("Nguồn: Forex Factory (faireconomy.media) · cập nhật " +
                             (store.calendarUpdatedAt.map { PulseFormat.clock($0) + " " + PulseFormat.shortDate($0) } ?? "—") +
                             " · giờ hiển thị theo múi giờ thiết bị")
                            .font(.system(size: 10))
                            .foregroundStyle(PulseTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(PulseTheme.background)
            .navigationTitle("Lịch kinh tế")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Mức ảnh hưởng", selection: $store.impactFilter) {
                            ForEach(ImpactFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.inline)
                        Button("Tải lại") {
                            Task { await store.loadCalendar(force: true) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
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
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .refreshable { await store.loadCalendar(force: true) }
        }
    }

    // MARK: - Sự kiện tiếp theo

    private func nextEventCard(_ event: EconomicEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PulseStatusPill(text: "Sắp diễn ra", color: PulseTheme.danger)
                Spacer()
                Text(PulseFormat.countdown(to: event.date))
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(PulseTheme.danger)
            }
            Text(event.flag + " " + event.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PulseTheme.textPrimary)
            HStack(spacing: 8) {
                Text(event.currencyName)
                Text("·")
                Text(PulseFormat.dayTitle(event.date))
                Text("·")
                Text(PulseFormat.clock(event.date))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(PulseTheme.textSecondary)
            HStack(spacing: 10) {
                if !event.forecast.isEmpty {
                    miniStat("Dự báo", event.forecast)
                }
                if !event.previous.isEmpty {
                    miniStat("Trước", event.previous)
                }
                Spacer()
                reminderButton(event)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(colors: [PulseTheme.danger.opacity(0.22), PulseTheme.surface],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PulseTheme.danger.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(PulseTheme.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(PulseTheme.textPrimary)
        }
    }

    // MARK: - Bộ lọc

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PulseTheme.teal)
                Text("Mức ảnh hưởng: " + store.impactFilter.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PulseTheme.textSecondary)
                Spacer()
                if store.currencyFilter != nil {
                    Button("Bỏ lọc tiền tệ") { store.currencyFilter = nil }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulseTheme.teal)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ImpactFilter.allCases) { filter in
                        PulseFilterChip(title: filter.title,
                                        isSelected: store.impactFilter == filter,
                                        tint: PulseTheme.teal) {
                            store.impactFilter = filter
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PulseFilterChip(title: "Tất cả tiền tệ",
                                    isSelected: store.currencyFilter == nil,
                                    tint: PulseTheme.violet) {
                        store.currencyFilter = nil
                    }
                    ForEach(majorCurrencies, id: \.self) { code in
                        PulseFilterChip(title: PulseSymbol.flag(forCurrency: code) + " " + code,
                                        isSelected: store.currencyFilter == code,
                                        tint: PulseTheme.violet) {
                            store.currencyFilter = store.currencyFilter == code ? nil : code
                        }
                    }
                }
            }
        }
    }

    private func reminderButton(_ event: EconomicEvent) -> some View {
        let reminded = CalendarReminderStore.minutes(for: event.id) != nil
        return Button {
            store.toggleReminder(for: event, minutes: 15)
        } label: {
            Label(reminded ? "Đã đặt nhắc" : "Nhắc trước 15 phút",
                  systemImage: reminded ? "bell.fill" : "bell")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(reminded ? PulseTheme.warning : PulseTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill((reminded ? PulseTheme.warning : PulseTheme.info).opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ngày

    private func daySection(_ day: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(PulseFormat.dayTitle(day.day))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PulseTheme.textPrimary)
                let high = day.events.filter { $0.impact == .high }.count
                if high > 0 {
                    Text("\(high) cao")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(PulseTheme.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(PulseTheme.danger.opacity(0.14)))
                }
                Spacer()
                Text("\(day.events.count) sự kiện")
                    .font(.system(size: 11))
                    .foregroundStyle(PulseTheme.textTertiary)
            }
            .padding(.horizontal, 4)

            ForEach(day.events) { event in
                EventRowView(event: event,
                             isReminded: CalendarReminderStore.minutes(for: event.id) != nil) {
                    store.toggleReminder(for: event, minutes: 15)
                }
            }
        }
        .padding(.top, 6)
    }
}
