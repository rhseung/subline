import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published var subscriptions: [Subscription] = [] {
        didSet { save() }
    }

    @Published var rates = ExchangeRates() {
        didSet { save() }
    }

    @Published var selectedID: Subscription.ID?
    @Published var ratesLastUpdated: Date? = UserDefaults.standard.object(forKey: "ratesLastUpdated") as? Date

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appending(path: "Subline", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "subline.json")
        load()
        replaceStaleDefaultRatesIfNeeded()

        if subscriptions.isEmpty {
            subscriptions = Self.samples
            selectedID = subscriptions.first?.id
        } else {
            selectedID = subscriptions.sorted(by: { $0.nextChargeDate < $1.nextChargeDate }).first?.id
        }

        fetchRatesIfNeeded()
    }

    var selectedSubscription: Subscription? {
        guard let selectedID else { return nil }
        return subscriptions.first { $0.id == selectedID }
    }

    func binding(for subscription: Subscription) -> BindingBox? {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return nil }
        return BindingBox(index: index)
    }

    func addSubscription(from preset: SubscriptionPreset) {
        let subscription = Subscription(
            name: preset.name,
            amount: preset.amount,
            currency: preset.currency,
            cycle: .monthly,
            billingPeriodValue: preset.billingPeriodValue,
            billingPeriodUnit: preset.billingPeriodUnit,
            planStartDate: Date(),
            status: .active,
            colorName: preset.colorName,
            symbolName: preset.symbolName
        )
        subscriptions.append(subscription)
        selectedID = subscription.id
    }

    func addSubscription() {
        let subscription = Subscription(
            name: "새 구독",
            amount: 9900,
            currency: .krw,
            cycle: .monthly,
            planStartDate: Date(),
            status: .active,
            colorName: "mint"
        )
        subscriptions.append(subscription)
        selectedID = subscription.id
    }

    func archiveSelected() {
        guard let selectedID, let index = subscriptions.firstIndex(where: { $0.id == selectedID }) else { return }
        subscriptions[index].status = .archived
    }

    func unarchiveSelected() {
        guard let selectedID, let index = subscriptions.firstIndex(where: { $0.id == selectedID }) else { return }
        subscriptions[index].status = .active
    }

    func deleteSelected() {
        guard let selectedID,
              let index = subscriptions.firstIndex(where: { $0.id == selectedID }) else {
            return
        }

        subscriptions.remove(at: index)
        self.selectedID = subscriptions.sorted(by: { $0.nextChargeDate < $1.nextChargeDate }).first?.id
    }

    func filteredSubscriptions(for filter: SidebarFilter) -> [Subscription] {
        subscriptions
            .filter { subscription in
                switch filter {
                case .all:
                    subscription.effectiveStatus != .archived
                case .thisMonth:
                    subscription.effectiveStatus != .archived && Calendar.current.isDate(subscription.nextChargeDate, equalTo: Date(), toGranularity: .month)
                case .trials:
                    subscription.effectiveStatus == .trial
                case .annual:
                    subscription.effectiveStatus != .archived && (
                        subscription.billingPeriodValue == 1 && subscription.billingPeriodUnit == .years ||
                        subscription.billingPeriodValue == 12 && subscription.billingPeriodUnit == .months
                    )
                case .foreign:
                    subscription.effectiveStatus != .archived && subscription.currency != .krw
                case .archived:
                    subscription.effectiveStatus == .archived
                }
            }
            .sorted { $0.nextChargeDate < $1.nextChargeDate }
    }

    func monthlyTotalKRW(excludingArchived: Bool = true) -> Decimal {
        subscriptions
            .filter { !excludingArchived || $0.effectiveStatus != .archived }
            .reduce(0) { result, subscription in
                result + rates.krwValue(for: subscription.userMonthlyEquivalent, currency: subscription.currency)
            }
    }

    func thisMonthTotalKRW() -> Decimal {
        subscriptions
            .filter { $0.effectiveStatus != .archived && Calendar.current.isDate($0.nextChargeDate, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { result, subscription in
                result + rates.krwValue(for: subscription.userAmount, currency: subscription.currency)
            }
    }

    var activeCount: Int {
        subscriptions.filter { $0.effectiveStatus != .archived }.count
    }

    var trialCount: Int {
        subscriptions.filter { $0.effectiveStatus == .trial }.count
    }

    var sharedCount: Int {
        subscriptions.filter { $0.effectiveStatus != .archived && $0.splitCount > 1 }.count
    }

    func monthlyCardChargeKRW(excludingArchived: Bool = true) -> Decimal {
        subscriptions
            .filter { !excludingArchived || $0.effectiveStatus != .archived }
            .reduce(0) { result, subscription in
                result + rates.krwValue(for: subscription.monthlyEquivalent, currency: subscription.currency)
            }
    }

    func thisMonthCardChargeKRW() -> Decimal {
        subscriptions
            .filter { $0.effectiveStatus != .archived && Calendar.current.isDate($0.nextChargeDate, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { result, subscription in
                result + rates.krwValue(for: subscription.amount, currency: subscription.currency)
            }
    }

    func upcoming(limit: Int = 6) -> [Subscription] {
        subscriptions
            .filter { $0.effectiveStatus != .archived && $0.nextChargeDate >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.nextChargeDate < $1.nextChargeDate }
            .prefix(limit)
            .map { $0 }
    }

    func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "subline-backup.json"
        panel.title = "데이터 내보내기"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = Snapshot(subscriptions: subscriptions, rates: rates)
        guard let data = try? JSONEncoder.subline.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "데이터 가져오기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder.subline.decode(Snapshot.self, from: data) else { return }
        subscriptions = snapshot.subscriptions
        rates = snapshot.rates
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder.subline.decode(Snapshot.self, from: data) else { return }
        subscriptions = snapshot.subscriptions
        rates = snapshot.rates
    }

    private func save() {
        let snapshot = Snapshot(subscriptions: subscriptions, rates: rates)
        guard let data = try? JSONEncoder.subline.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func fetchRatesIfNeeded() {
        let lastFetch = UserDefaults.standard.object(forKey: "ratesLastUpdated") as? Date
        guard lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 86400 else { return }
        Task { await fetchRates() }
    }

    func fetchRates() async {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=KRW&to=USD,JPY,EUR,GBP") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

        struct FrankfurterResponse: Decodable {
            let rates: [String: Double]
        }
        guard let response = try? JSONDecoder().decode(FrankfurterResponse.self, from: data) else { return }

        if let usd = response.rates["USD"], usd > 0 { rates.usd = Decimal(1.0 / usd) }
        if let jpy = response.rates["JPY"], jpy > 0 { rates.jpy = Decimal(1.0 / jpy) }
        if let eur = response.rates["EUR"], eur > 0 { rates.eur = Decimal(1.0 / eur) }
        if let gbp = response.rates["GBP"], gbp > 0 { rates.gbp = Decimal(1.0 / gbp) }

        let now = Date()
        ratesLastUpdated = now
        UserDefaults.standard.set(now, forKey: "ratesLastUpdated")
    }

    private func replaceStaleDefaultRatesIfNeeded() {
        let staleDefaults = ExchangeRates(usd: 1380, jpy: 9.45, eur: 1490, gbp: 1740)
        guard rates.usd == staleDefaults.usd,
              rates.jpy == staleDefaults.jpy,
              rates.eur == staleDefaults.eur,
              rates.gbp == staleDefaults.gbp else {
            return
        }

        rates = ExchangeRates()
    }

    private var iconsDirectory: URL {
        fileURL.deletingLastPathComponent().appending(path: "icons", directoryHint: .isDirectory)
    }

    /// Lets the user pick an image file, copies it into the app's storage,
    /// and switches the subscription to photo mode.
    func chooseIconImage(for id: Subscription.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "아이콘 이미지 선택"
        guard panel.runModal() == .OK, let source = panel.url,
              let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }

        removeStoredIconFile(for: subscriptions[index])

        try? FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let destination = iconsDirectory.appending(path: "\(id.uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            return
        }

        subscriptions[index].iconImageURL = destination.absoluteString
        subscriptions[index].iconStyle = .image
        if let hex = ServiceAppearance.dominantColorHex(of: destination) {
            subscriptions[index].colorName = hex
        }
    }

    /// Clears a custom photo and falls back to the symbol style.
    func removeIconImage(for id: Subscription.ID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        removeStoredIconFile(for: subscriptions[index])
        subscriptions[index].iconImageURL = nil
        subscriptions[index].iconStyle = .symbol
    }

    private func removeStoredIconFile(for subscription: Subscription) {
        guard let urlString = subscription.iconImageURL,
              let url = URL(string: urlString), url.isFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    struct BindingBox {
        let index: Int
    }

    private struct Snapshot: Codable {
        var subscriptions: [Subscription]
        var rates: ExchangeRates
    }

    private static var samples: [Subscription] {
        let calendar = Calendar.current
        let now = Date()

        return [
            Subscription(
                name: "ChatGPT",
                amount: 20,
                currency: .usd,
                cycle: .monthly,
                planStartDate: calendar.date(byAdding: .day, value: -25, to: now) ?? now,
                status: .active,
                cancellationURL: "https://chatgpt.com",
                notes: "업무와 리서치용",
                colorName: "green",
                symbolName: "bubble.left.and.text.bubble.right"
            ),
            Subscription(
                name: "iCloud+",
                amount: 3300,
                currency: .krw,
                cycle: .monthly,
                planStartDate: calendar.date(byAdding: .day, value: -18, to: now) ?? now,
                status: .active,
                colorName: "blue",
                symbolName: "icloud"
            ),
            Subscription(
                name: "Figma",
                amount: 144,
                currency: .usd,
                cycle: .yearly,
                planStartDate: calendar.date(byAdding: .month, value: -9, to: now) ?? now,
                status: .active,
                notes: "연간 결제",
                colorName: "purple",
                symbolName: "paintpalette"
            ),
            Subscription(
                name: "스트리밍 무료 체험",
                amount: 14900,
                currency: .krw,
                cycle: .monthly,
                planStartDate: calendar.date(byAdding: .day, value: 14, to: now) ?? now,
                trialStartDate: now,
                trialDurationValue: 14,
                trialDurationUnit: .days,
                status: .trial,
                notes: "유료 전환 전에 해지 검토",
                colorName: "orange",
                symbolName: "play.tv"
            )
        ]
    }
}

private extension JSONEncoder {
    static var subline: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var subline: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
