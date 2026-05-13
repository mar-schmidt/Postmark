import SwiftUI

struct AccountAvatar: View {
    let account: Account
    var size: CGFloat = 36

    var body: some View {
        Text(String(account.email.prefix(1)).uppercased())
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: account.avatarGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
            .shadow(
                color: account.avatarGradient.last?.opacity(0.33) ?? .clear,
                radius: 4,
                y: 1
            )
    }
}

extension Account {
    var avatarGradient: [Color] {
        let palettes: [[Color]] = [
            [Color(hex: "5B8DEF"), Color(hex: "7B5EA7")],
            [Color(hex: "34C759"), Color(hex: "00A86B")],
            [Color(hex: "FF9500"), Color(hex: "FF6B35")],
            [Color(hex: "AF52DE"), Color(hex: "FF2D55")],
            [Color(hex: "00C7BE"), Color(hex: "007AFF")]
        ]
        let index = abs(email.hashValue) % palettes.count
        return palettes[index]
    }
}

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview("Default Avatar") {
    let account = Account(
        id: UUID(),
        email: "marcus@gmail.com",
        displayName: "Marcus",
        isActiveInbox: true,
        emailOpenBehavior: .openDetail,
        selectedLabelIDs: ["INBOX"]
    )
    return AccountAvatar(account: account)
        .padding()
        .frame(width: 100, height: 100)
}
