import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SubscriptionStore
    @State private var filter: SidebarFilter = .all
    @State private var viewMode: SubscriptionViewMode = .list
    @State private var isQuickAddPresented = false

    private var filtered: [Subscription] {
        store.filteredSubscriptions(for: filter)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $filter)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            SubscriptionContentView(viewMode: viewMode, filter: filter, subscriptions: filtered)
                .navigationTitle(filter.title)
                .toolbar {
                    ToolbarItem {
                        Picker("보기", selection: $viewMode) {
                            ForEach(SubscriptionViewMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    ToolbarItem {
                        Button {
                            isQuickAddPresented = true
                        } label: {
                            Label("추가", systemImage: "plus")
                        }
                    }
                }
        } detail: {
            DetailColumnView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 460)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isQuickAddPresented) {
            QuickAddView()
        }
    }
}

enum SubscriptionViewMode: String, CaseIterable, Identifiable {
    case list
    case calendar
    case board

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "목록"
        case .calendar: "캘린더"
        case .board: "보드"
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .calendar: "calendar"
        case .board: "rectangle.3.group"
        }
    }
}

struct SubscriptionContentView: View {
    let viewMode: SubscriptionViewMode
    let filter: SidebarFilter
    let subscriptions: [Subscription]

    var body: some View {
        switch viewMode {
        case .list:
            SubscriptionListView(filter: filter, subscriptions: subscriptions)
        case .calendar:
            CalendarMonthView(subscriptions: subscriptions)
        case .board:
            BoardView(subscriptions: subscriptions)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: SubscriptionStore
    @Binding var selection: SidebarFilter

    var body: some View {
        List(selection: $selection) {
            Section("Subline") {
                ForEach(SidebarFilter.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }

            Section("요약") {
                let thisMonthShare = store.thisMonthTotalKRW()
                let thisMonthCharge = store.thisMonthCardChargeKRW()
                MetricRow(
                    title: "이번 달 비용",
                    value: Formatters.krw(thisMonthShare),
                    subtitle: thisMonthShare != thisMonthCharge ? "청구 \(Formatters.krw(thisMonthCharge))" : nil
                )

                let monthlyShare = store.monthlyTotalKRW()
                let monthlyCharge = store.monthlyCardChargeKRW()
                MetricRow(
                    title: "월평균",
                    value: Formatters.krw(monthlyShare),
                    subtitle: monthlyShare != monthlyCharge ? "청구 \(Formatters.krw(monthlyCharge))" : nil
                )

                MetricRow(
                    title: "연간 예상",
                    value: Formatters.krw(monthlyShare * 12),
                    subtitle: monthlyShare != monthlyCharge ? "청구 \(Formatters.krw(monthlyCharge * 12))" : nil
                )
            }

            Section("구독") {
                MetricRow(title: "활성 구독", value: "\(store.activeCount)개")
                if store.trialCount > 0 {
                    MetricRow(title: "무료 체험 중", value: "\(store.trialCount)개")
                }
                if store.sharedCount > 0 {
                    MetricRow(title: "공유 구독", value: "\(store.sharedCount)개")
                }
            }

            if let next = store.upcoming(limit: 1).first {
                Section("다음 결제") {
                    MetricRow(
                        title: Formatters.day.string(from: next.nextChargeDate),
                        value: Formatters.money(next.userAmount, currency: next.currency),
                        subtitle: next.name
                    )
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private enum BillingGroup: String, CaseIterable {
    case weekly = "주간"
    case monthly = "월간"
    case yearly = "연간"
    case other = "기타"

    static func of(_ s: Subscription) -> BillingGroup {
        switch (s.billingPeriodUnit, s.billingPeriodValue) {
        case (.weeks, _):          return .weekly
        case (.months, 1):         return .monthly
        case (.months, 12):        return .yearly
        case (.years, 1):          return .yearly
        default:                   return .other
        }
    }
}

struct SubscriptionListView: View {
    @EnvironmentObject private var store: SubscriptionStore
    let filter: SidebarFilter
    let subscriptions: [Subscription]

    private var grouped: [(group: BillingGroup, items: [Subscription])] {
        BillingGroup.allCases.compactMap { group in
            let items = subscriptions.filter { BillingGroup.of($0) == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    private func subtotal(for items: [Subscription]) -> Decimal {
        items.reduce(0) { $0 + store.rates.krwValue(for: $1.userMonthlyEquivalent, currency: $1.currency) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardStrip()
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            if subscriptions.isEmpty {
                ContentUnavailableView("구독 없음", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(grouped, id: \.group.rawValue) { group, items in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.rawValue)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Formatters.krw(subtotal(for: items)))/월")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)

                                ForEach(items) { subscription in
                                    SubscriptionCard(subscription: subscription)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                }
            }
        }
    }
}

struct SubscriptionCard: View {
    let subscription: Subscription
    @EnvironmentObject private var store: SubscriptionStore

    private var isSelected: Bool { store.selectedID == subscription.id }
    private var isOverdue: Bool { subscription.nextChargeDate < Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        Button {
            store.selectedID = isSelected ? nil : subscription.id
        } label: {
            HStack(spacing: 12) {
                ServiceIcon(subscription: subscription, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(subscription.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(subscription.effectiveStatus.title)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                        if subscription.splitCount > 1 {
                            Label("\(subscription.splitCount)명", systemImage: "person.2.fill")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    Text("결제일 \(Formatters.day.string(from: subscription.nextChargeDate))")
                        .font(.caption)
                        .foregroundStyle(isOverdue ? .red : .secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formatters.money(subscription.userAmount, currency: subscription.currency))
                        .font(.subheadline.weight(.semibold))
                    if subscription.splitCount > 1 {
                        if subscription.currency != .krw {
                            Text("총 \(Formatters.money(subscription.amount, currency: subscription.currency)) · \(Formatters.krw(store.rates.krwValue(for: subscription.userAmount, currency: subscription.currency))) · \(subscription.billingPeriodTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("총 \(Formatters.money(subscription.amount, currency: subscription.currency)) · \(subscription.billingPeriodTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if subscription.currency != .krw {
                        Text("\(Formatters.krw(store.rates.krwValue(for: subscription.amount, currency: subscription.currency))) · \(subscription.billingPeriodTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(subscription.billingPeriodTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .sublineGlass(cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? ServiceAppearance.color(named: subscription.colorName).opacity(0.7) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct DashboardStrip: View {
    @EnvironmentObject private var store: SubscriptionStore

    var body: some View {
        HStack(spacing: 12) {
            let myShare = store.thisMonthTotalKRW()
            let cardCharge = store.thisMonthCardChargeKRW()
            SummaryTile(
                title: "이번 달 비용",
                value: Formatters.krw(myShare),
                subtitle: myShare != cardCharge ? "청구 \(Formatters.krw(cardCharge))" : nil,
                symbol: "calendar"
            )
            let myMonthly = store.monthlyTotalKRW()
            let cardMonthly = store.monthlyCardChargeKRW()
            SummaryTile(
                title: "월평균 비용",
                value: Formatters.krw(myMonthly),
                subtitle: myMonthly != cardMonthly ? "청구 \(Formatters.krw(cardMonthly))" : nil,
                symbol: "chart.line.uptrend.xyaxis"
            )
            SummaryTile(title: "예정 항목", value: "\(store.upcoming(limit: 99).count)개", symbol: "bell")
        }
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 30, height: 30)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72)
        .sublineGlass(cornerRadius: 14)
    }
}

struct ServiceCell: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 10) {
            ServiceIcon(subscription: subscription, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .fontWeight(.medium)
                Text(subscription.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DetailColumnView: View {
    @EnvironmentObject private var store: SubscriptionStore

    var body: some View {
        Group {
            if let selected = store.selectedSubscription,
               let bindingBox = store.binding(for: selected) {
                SubscriptionEditor(subscription: $store.subscriptions[bindingBox.index])
            } else {
                ContentUnavailableView("선택한 구독이 없습니다", systemImage: "rectangle.stack")
            }
        }
    }
}

struct SubscriptionEditor: View {
    @Binding var subscription: Subscription
    @EnvironmentObject private var store: SubscriptionStore
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderCard(subscription: subscription)

                EditorSection("기본 정보") {
                    EditorRow("이름") { TextField("", text: $subscription.name).textFieldStyle(.plain).multilineTextAlignment(.trailing) }
                }

                EditorSection("표시") {
                    EditorRow("색상") {
                        ColorSwatchPicker(selection: $subscription.colorName)
                            .labelsHidden()
                    }
                    Divider().padding(.leading, 14)
                    EditorRow("아이콘 색상") {
                        Picker("", selection: $subscription.symbolForeground) {
                            Text("흰색").tag("white")
                            Text("검정").tag("black")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider().padding(.leading, 14)
                    IconGridPicker(selection: $subscription.symbolName)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }

                EditorSection("결제") {
                    EditorRow("금액") { DecimalField("", value: $subscription.amount).multilineTextAlignment(.trailing) }
                    Divider().padding(.leading, 14)
                    EditorRow("통화") {
                        Picker("", selection: $subscription.currency) {
                            ForEach(CurrencyCode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                    }
                    Divider().padding(.leading, 14)
                    EditorRow("결제 주기") {
                        Stepper("\(subscription.billingPeriodValue)\(subscription.billingPeriodUnit.title)마다", value: $subscription.billingPeriodValue, in: 1...999)
                    }
                    Divider().padding(.leading, 14)
                    EditorRow("주기 단위") {
                        Picker("", selection: $subscription.billingPeriodUnit) {
                            ForEach(BillingPeriodUnit.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    Divider().padding(.leading, 14)
                    if subscription.trialStartDate == nil {
                        EditorRow("요금제 시작일") {
                            DatePicker("", selection: $subscription.planStartDate, displayedComponents: .date).labelsHidden()
                        }
                    } else {
                        EditorRow("유료 요금제 시작일") {
                            Text(Formatters.day.string(from: subscription.effectiveFirstChargeDate)).foregroundStyle(.secondary)
                        }
                    }
                    Divider().padding(.leading, 14)
                    EditorRow("다음 결제일") {
                        Text(Formatters.day.string(from: subscription.nextChargeDate)).foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 14)
                    EditorRow("공유 인원") {
                        Stepper(
                            subscription.splitCount == 1 ? "혼자" : "\(subscription.splitCount)명",
                            value: $subscription.splitCount,
                            in: 1...20
                        )
                    }
                }

                EditorSection("무료 체험") {
                    EditorRow("무료 체험") { Toggle("", isOn: trialEnabled).labelsHidden() }
                    if subscription.trialStartDate != nil {
                        Divider().padding(.leading, 14)
                        EditorRow("시작일") {
                            DatePicker("", selection: trialStartDate, displayedComponents: .date).labelsHidden()
                        }
                        Divider().padding(.leading, 14)
                        EditorRow("기간") {
                            Stepper("\(subscription.trialDurationValue)\(subscription.trialDurationUnit.title)", value: $subscription.trialDurationValue, in: 1...999)
                        }
                        Divider().padding(.leading, 14)
                        EditorRow("단위") {
                            Picker("", selection: $subscription.trialDurationUnit) {
                                ForEach(TrialDurationUnit.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                        Divider().padding(.leading, 14)
                        EditorRow("종료일") {
                            Text(subscription.trialEndDate.map { Formatters.day.string(from: $0) } ?? "-").foregroundStyle(.secondary)
                        }
                    }
                }

                EditorSection("세부 정보") {
                    EditorRow("해지 URL") { TextField("", text: $subscription.cancellationURL).textFieldStyle(.plain).multilineTextAlignment(.trailing) }
                    Divider().padding(.leading, 14)
                    TextField("메모", text: $subscription.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }

                EditorSection("환율") {
                    EditorRow("USD") { RateText(store.rates.usd) }
                    Divider().padding(.leading, 14)
                    EditorRow("JPY") { RateText(store.rates.jpy) }
                    Divider().padding(.leading, 14)
                    EditorRow("EUR") { RateText(store.rates.eur) }
                    Divider().padding(.leading, 14)
                    EditorRow("GBP") { RateText(store.rates.gbp) }
                    Divider().padding(.leading, 14)
                    EditorRow("업데이트") {
                        HStack(spacing: 8) {
                            if let updated = store.ratesLastUpdated {
                                Text(updated, style: .relative)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("없음").foregroundStyle(.secondary)
                            }
                            Button("갱신") { Task { await store.fetchRates() } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(22)
        }
        .toolbar {
            ToolbarItem {
                if store.selectedSubscription?.effectiveStatus == .archived {
                    Button {
                        store.unarchiveSelected()
                    } label: {
                        Label("보관 해제", systemImage: "archivebox.fill")
                    }
                } else {
                    Button(role: .destructive) {
                        store.archiveSelected()
                    } label: {
                        Label("보관", systemImage: "archivebox")
                    }
                }
            }
            ToolbarItem {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "이 구독을 삭제할까요?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                store.deleteSelected()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 구독은 되돌릴 수 없습니다.")
        }
    }

    private var trialEnabled: Binding<Bool> {
        Binding {
            subscription.trialStartDate != nil
        } set: { isEnabled in
            subscription.trialStartDate = isEnabled ? (subscription.trialStartDate ?? Date()) : nil
            if !isEnabled && subscription.status == .trial {
                subscription.status = .active
            }
        }
    }

    private var trialStartDate: Binding<Date> {
        Binding {
            subscription.trialStartDate ?? Date()
        } set: { newValue in
            subscription.trialStartDate = newValue
        }
    }
}

struct HeaderCard: View {
    let subscription: Subscription
    @EnvironmentObject private var store: SubscriptionStore

    private var brandColor: Color {
        ServiceAppearance.color(named: subscription.colorName)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Ellipse()
                    .fill(brandColor.opacity(0.45))
                    .frame(width: 130, height: 55)
                    .blur(radius: 28)

                ServiceIcon(subscription: subscription, size: 64)
                    .shadow(color: brandColor.opacity(0.55), radius: 16, x: 0, y: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)

            VStack(spacing: 4) {
                Text(subscription.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                Text(subscription.billingPeriodTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .padding(.bottom, 18)

            Divider().padding(.horizontal, 18)

            VStack(spacing: 0) {
                HeaderInfoRow(label: subscription.splitCount > 1 ? "내 부담" : "결제 금액",
                              value: Formatters.money(subscription.userAmount, currency: subscription.currency))
                if subscription.splitCount > 1 {
                    HeaderInfoRow(label: "총액 (\(subscription.splitCount)명)",
                                  value: Formatters.money(subscription.amount, currency: subscription.currency))
                }
                if subscription.currency != .krw {
                    HeaderInfoRow(label: "원화 환산",
                                  value: Formatters.krw(store.rates.krwValue(for: subscription.userAmount, currency: subscription.currency)))
                }
                HeaderInfoRow(label: "다음 결제일",
                              value: Formatters.day.string(from: subscription.nextChargeDate),
                              isLast: true)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
        }
        .sublineGlass(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RadialGradient(
                    colors: [brandColor.opacity(0.22), .clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 10,
                    endRadius: 140
                ))
                .allowsHitTesting(false)
        }
    }
}

struct HeaderInfoRow: View {
    let label: String
    let value: String
    var isLast: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast { Divider() }
        }
    }
}

struct CalendarMonthView: View {
    @EnvironmentObject private var store: SubscriptionStore
    let subscriptions: [Subscription]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    private var monthStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: monthStart)
    }

    private var days: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingEmptyDays = max(firstWeekday - 1, 0)
        let monthDays = range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
        return Array(repeating: nil, count: leadingEmptyDays) + monthDays
    }

    private var eventsByDay: [Date: [SubscriptionEvent]] {
        let calendar = Calendar.current
        let monthEvents = subscriptions.flatMap {
            SubscriptionEvent.events(for: $0, rates: store.rates, daysAhead: 370)
        }
        .filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }

        return Dictionary(grouping: monthEvents) { event in
            calendar.startOfDay(for: event.date)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardStrip()
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(monthTitle)
                        .font(.title2.weight(.semibold))

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(weekdays, id: \.self) { weekday in
                            Text(weekday)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                            CalendarDayCell(
                                date: date,
                                events: date.map { eventsByDay[Calendar.current.startOfDay(for: $0)] ?? [] } ?? []
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

struct CalendarDayCell: View {
    @EnvironmentObject private var store: SubscriptionStore
    let date: Date?
    let events: [SubscriptionEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date {
                HStack {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if Calendar.current.isDateInToday(date) {
                        Circle()
                            .fill(.tint)
                            .frame(width: 6, height: 6)
                    }
                }

                ForEach(events.prefix(3)) { event in
                    Button {
                        store.selectedID = event.subscription.id
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ServiceAppearance.color(named: event.subscription.colorName))
                                .frame(width: 6, height: 6)
                            Text(event.subscription.name)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if events.count > 3 {
                    Button {
                        if let firstHidden = events.dropFirst(3).first {
                            store.selectedID = firstHidden.subscription.id
                        }
                    } label: {
                        Text("+\(events.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minHeight: 92, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .sublineGlass(cornerRadius: 12)
        .opacity(date == nil ? 0 : 1)
    }
}

struct BoardView: View {
    @EnvironmentObject private var store: SubscriptionStore
    let subscriptions: [Subscription]

    private var columns: [BoardColumn] {
        [
            BoardColumn(title: "무료체험", symbol: "clock.badge.exclamationmark", subscriptions: subscriptions.filter { $0.trialEndDate != nil }),
            BoardColumn(title: "이번 달", symbol: "calendar", subscriptions: subscriptions.filter { Calendar.current.isDate($0.nextChargeDate, equalTo: Date(), toGranularity: .month) }),
            BoardColumn(title: "해외 결제", symbol: "globe", subscriptions: subscriptions.filter { $0.currency != .krw }),
            BoardColumn(title: "장기 주기", symbol: "arrow.triangle.2.circlepath", subscriptions: subscriptions.filter { $0.monthsPerCharge >= 6 })
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardStrip()
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns) { column in
                        BoardColumnView(column: column)
                            .frame(width: 250)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct BoardColumn: Identifiable {
    let title: String
    let symbol: String
    let subscriptions: [Subscription]

    var id: String { title }
}

struct BoardColumnView: View {
    let column: BoardColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(column.title, systemImage: column.symbol)
                    .font(.headline)
                Spacer()
                Text("\(column.subscriptions.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if column.subscriptions.isEmpty {
                Text("항목 없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 74)
            } else {
                ForEach(column.subscriptions.sorted { $0.nextChargeDate < $1.nextChargeDate }) { subscription in
                    BoardCard(subscription: subscription)
                }
            }
        }
        .padding(14)
        .sublineGlass(cornerRadius: 16)
    }
}

struct BoardCard: View {
    let subscription: Subscription
    @EnvironmentObject private var store: SubscriptionStore

    var body: some View {
        Button {
            store.selectedID = subscription.id
        } label: {
            HStack(spacing: 10) {
                ServiceIcon(subscription: subscription, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(subscription.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(Formatters.day.string(from: subscription.nextChargeDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatters.krw(store.rates.krwValue(for: subscription.userMonthlyEquivalent, currency: subscription.currency)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SubscriptionEvent: Identifiable {
    let id: String
    let subscription: Subscription
    let date: Date
    let kind: Kind
    let amountText: String?

    enum Kind {
        case trialEnds
        case charge
    }

    var kindTitle: String {
        switch kind {
        case .trialEnds: "무료체험 종료"
        case .charge: "결제"
        }
    }

    var subtitle: String {
        switch kind {
        case .trialEnds: "유료 요금제로 전환됩니다"
        case .charge: subscription.billingPeriodTitle
        }
    }

    static func events(for subscription: Subscription, rates: ExchangeRates, daysAhead: Int = 90) -> [SubscriptionEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let horizon = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
        var events: [SubscriptionEvent] = []

        if let trialEndDate = subscription.trialEndDate,
           trialEndDate >= today,
           trialEndDate <= horizon {
            events.append(
                SubscriptionEvent(
                    id: "\(subscription.id)-trial-\(trialEndDate.timeIntervalSince1970)",
                    subscription: subscription,
                    date: trialEndDate,
                    kind: .trialEnds,
                    amountText: nil
                )
            )
        }

        var chargeDate = subscription.nextChargeDate
        while chargeDate <= horizon {
            events.append(
                SubscriptionEvent(
                    id: "\(subscription.id)-charge-\(chargeDate.timeIntervalSince1970)",
                    subscription: subscription,
                    date: chargeDate,
                    kind: .charge,
                    amountText: Formatters.krw(rates.krwValue(for: subscription.userAmount, currency: subscription.currency))
                )
            )
            chargeDate = subscription.billingPeriodUnit.date(after: chargeDate, value: subscription.billingPeriodValue, calendar: calendar)
        }

        return events
    }
}

struct ServiceIcon: View {
    let subscription: Subscription
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(ServiceAppearance.color(named: subscription.colorName).gradient)
            Image(systemName: subscription.symbolName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(subscription.symbolForeground == "black" ? Color.black : Color.white)
        }
        .frame(width: size, height: size)
    }
}

struct IconGridPicker: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 6), count: 7)

    var body: some View {
        HStack(alignment: .top) {
            Text("아이콘")
                .fixedSize()
            Spacer()
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ServiceAppearance.symbols) { option in
                    Button {
                        selection = option.name
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == option.name ? Color.accentColor : Color.primary.opacity(0.08))
                                .frame(width: 28, height: 28)
                            Image(systemName: option.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(selection == option.name ? .white : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                    .accessibilityLabel(option.title)
                }
            }
            .fixedSize()
        }
    }
}

struct ColorSwatchPicker: View {
    @Binding var selection: String
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented = true
        } label: {
            Circle()
                .fill(ServiceAppearance.color(named: selection).gradient)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 6), spacing: 6) {
                    ForEach(ServiceAppearance.colors) { option in
                        Button {
                            selection = option.name
                            isPopoverPresented = false
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color.gradient)
                                    .frame(width: 28, height: 28)
                                if selection == option.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(option.color.luminance > 0.5 ? .black : .white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }

                Divider()

                ColorPicker("사용자 지정", selection: Binding(
                    get: { ServiceAppearance.color(named: selection) },
                    set: { selection = $0.hexString }
                ), supportsOpacity: false)
                .font(.caption)
            }
            .padding(12)
            .frame(width: 216)
        }
    }
}

enum ServiceAppearance {
    static let colors: [ColorOption] = [
        ColorOption(name: "blue", title: "블루", color: .blue),
        ColorOption(name: "green", title: "그린", color: .green),
        ColorOption(name: "mint", title: "민트", color: .mint),
        ColorOption(name: "teal", title: "틸", color: .teal),
        ColorOption(name: "cyan", title: "시안", color: .cyan),
        ColorOption(name: "purple", title: "퍼플", color: .purple),
        ColorOption(name: "indigo", title: "인디고", color: .indigo),
        ColorOption(name: "orange", title: "오렌지", color: .orange),
        ColorOption(name: "yellow", title: "옐로", color: .yellow),
        ColorOption(name: "pink", title: "핑크", color: .pink),
        ColorOption(name: "red", title: "레드", color: .red),
        ColorOption(name: "gray", title: "그레이", color: .gray)
    ]

    static let symbols: [SymbolOption] = [
        SymbolOption(name: "repeat", title: "반복"),
        SymbolOption(name: "sparkles", title: "AI"),
        SymbolOption(name: "waveform", title: "AI/음성"),
        SymbolOption(name: "brain", title: "AI/브레인"),
        SymbolOption(name: "icloud", title: "클라우드"),
        SymbolOption(name: "cloud.fill", title: "클라우드"),
        SymbolOption(name: "play.tv", title: "스트리밍"),
        SymbolOption(name: "music.note", title: "음악"),
        SymbolOption(name: "headphones", title: "헤드폰"),
        SymbolOption(name: "music.note.list", title: "재생목록"),
        SymbolOption(name: "message.fill", title: "메신저"),
        SymbolOption(name: "paintpalette", title: "디자인"),
        SymbolOption(name: "gamecontroller", title: "게임"),
        SymbolOption(name: "newspaper", title: "뉴스"),
        SymbolOption(name: "shippingbox", title: "배송"),
        SymbolOption(name: "fork.knife", title: "음식/배달"),
        SymbolOption(name: "cart.fill", title: "쇼핑"),
        SymbolOption(name: "creditcard", title: "카드"),
        SymbolOption(name: "key.fill", title: "비밀번호"),
        SymbolOption(name: "lock.shield.fill", title: "보안"),
        SymbolOption(name: "checklist", title: "할일"),
        SymbolOption(name: "terminal.fill", title: "터미널"),
        SymbolOption(name: "chevron.left.forwardslash.chevron.right", title: "코드"),
        SymbolOption(name: "square.stack.3d.up.fill", title: "앱"),
        SymbolOption(name: "doc.fill", title: "문서"),
        SymbolOption(name: "heart.fill", title: "건강"),
        SymbolOption(name: "person.crop.circle.fill", title: "계정"),
        SymbolOption(name: "globe", title: "글로벌")
    ]

    static func color(named name: String) -> Color {
        if name.hasPrefix("#") { return Color(hex: name) }
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "purple": return .purple
        case "indigo": return .indigo
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink": return .pink
        case "red": return .red
        case "gray": return .gray
        default: return colors.first { $0.name == name }?.color ?? .blue
        }
    }

    struct ColorOption: Identifiable {
        let name: String
        let title: String
        let color: Color

        var id: String { name }
    }

    struct SymbolOption: Identifiable {
        let name: String
        let title: String

        var id: String { name }
    }
}

struct EditorSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct EditorRow<Content: View>: View {
    let label: String
    let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return String(format: "#%02X%02X%02X",
            Int((ns.redComponent * 255).rounded()),
            Int((ns.greenComponent * 255).rounded()),
            Int((ns.blueComponent * 255).rounded())
        )
    }

    var luminance: Double {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Double(ns.redComponent)
        let g = Double(ns.greenComponent)
        let b = Double(ns.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

struct RateText: View {
    let rate: Decimal
    init(_ rate: Decimal) { self.rate = rate }

    var body: some View {
        Text("₩\(rate, format: .number.precision(.fractionLength(0...2)))")
            .foregroundStyle(.secondary)
    }
}

struct DecimalField: View {
    let title: String
    @Binding var value: Decimal

    init(_ title: String, value: Binding<Decimal>) {
        self.title = title
        self._value = value
    }

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.plain)
    }
}

struct QuickAddView: View {
    @EnvironmentObject private var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var categories: [(String, [SubscriptionPreset])] {
        let filtered = searchText.isEmpty
            ? SubscriptionPreset.all
            : SubscriptionPreset.all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        let grouped = Dictionary(grouping: filtered) { $0.category }
        let order = ["스트리밍", "클라우드", "AI", "생산성", "개발", "기타"]
        return order.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("구독 추가")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("서비스 검색", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if categories.isEmpty {
                        Text("검색 결과 없음")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 30)
                    } else {
                        ForEach(categories, id: \.0) { category, presets in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                    spacing: 10
                                ) {
                                    ForEach(presets) { preset in
                                        PresetButton(preset: preset) {
                                            store.addSubscription(from: preset)
                                            dismiss()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Divider()

            Button {
                store.addSubscription()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("직접 입력")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
        }
        .frame(width: 440, height: 530)
    }
}

struct PresetButton: View {
    let preset: SubscriptionPreset
    let action: () -> Void

    private var color: Color { ServiceAppearance.color(named: preset.colorName) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.gradient)
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 3)

                Text(preset.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
