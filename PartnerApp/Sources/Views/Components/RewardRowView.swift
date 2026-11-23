import SwiftUI

/// Một dòng hoa hồng dùng chung cho màn Tổng quan và màn Hoa hồng.
struct RewardRowView: View {
    let row: RewardRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.date(row.rewardDate))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PartnerTheme.textPrimary)

                HStack(spacing: 6) {
                    if let country = row.country, !country.isEmpty {
                        Text(country)
                            .font(.system(size: 11))
                            .foregroundStyle(PartnerTheme.textSecondary)
                    }

                    if let account = row.clientAccount, !account.isEmpty {
                        Text("••" + String(account.suffix(4)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(PartnerTheme.textTertiary)
                    }
                }

                if let type = row.clientAccountType, !type.isEmpty {
                    Text(type.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(PartnerTheme.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.usd(row.rewardUsdDecimal))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PartnerTheme.accent)

                Text(Fmt.lots(row.volumeLots) + " lots")
                    .font(.system(size: 10))
                    .foregroundStyle(PartnerTheme.textSecondary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
