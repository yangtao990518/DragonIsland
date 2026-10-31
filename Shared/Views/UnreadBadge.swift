import SwiftUI

struct UnreadBadge: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white).padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                .background(Color(red: 0.95, green: 0.22, blue: 0.28), in: Capsule())
                .overlay(Capsule().stroke(.white, lineWidth: 1.2))
                .accessibilityLabel("\(count) 条未读消息")
        }
    }
}
