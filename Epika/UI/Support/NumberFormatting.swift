import Foundation

// UI表示で一貫した3桁区切りを行うための FormatStyle ヘルパー。
// ja_JP ロケールを固定し、iOS 15 以降で提供される .formatted(_:) を利用する。
enum NumberFormatting {
    static let locale = Locale(identifier: "ja_JP")
}

extension BinaryInteger {
    func formattedWithComma(locale: Locale = NumberFormatting.locale) -> String {
        if let value = self as? Int {
            return value.formatted(.number.locale(locale))
        }
        if let value = Int(exactly: self) {
            return value.formatted(.number.locale(locale))
        }
        var style = FloatingPointFormatStyle<Double>.number.locale(locale)
        style = style.precision(.fractionLength(0...0))
        return Double(self).formatted(style)
    }
}

extension BinaryFloatingPoint {
    func formattedWithComma(maximumFractionDigits: Int = 2,
                            locale: Locale = NumberFormatting.locale) -> String {
        let digits = max(0, maximumFractionDigits)
        var style = FloatingPointFormatStyle<Double>.number.locale(locale)
        style = style.precision(.fractionLength(0...digits))
        return Double(self).formatted(style)
    }
}
