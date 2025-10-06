import SwiftUI

typealias ItemCurrencyType = RuntimeEquipment.CurrencyType

struct PriceView: View {
    let price: Int
    let currencyType: ItemCurrencyType
    let isAffordable: Bool

    init(price: Int, currencyType: ItemCurrencyType = .gold, isAffordable: Bool = true) {
        self.price = price
        self.currencyType = currencyType
        self.isAffordable = isAffordable
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(formatPrice(price))
                .font(.headline)
                .foregroundColor(.primary)

            currencyIcon
                .foregroundColor(.primary)
        }
    }

    private var currencyIcon: some View {
        Group {
            switch currencyType {
            case .gold:
                Text("GP")
                    .font(.caption)
                    .bold()
            case .catTicket:
                Image(systemName: "ticket.fill")
                    .font(.caption)
            case .gem:
                Image(systemName: "diamond.fill")
                    .font(.caption)
            }
        }
    }

    private func formatPrice(_ price: Int) -> String {
        if price >= 1000000 {
            return String(format: "%.1fM", Double(price) / 1000000.0)
        } else if price >= 1000 {
            return String(format: "%.1fK", Double(price) / 1000.0)
        } else {
            return "\(price)"
        }
    }
}
 
