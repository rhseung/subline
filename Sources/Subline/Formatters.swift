import Foundation

enum Formatters {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func money(_ value: Decimal, currency: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = currency == .krw || currency == .jpy ? 0 : 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func krw(_ value: Decimal) -> String {
        money(value, currency: .krw)
    }
}
