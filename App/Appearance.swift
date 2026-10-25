import SwiftUI
import UIKit

enum AppPalette {
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = adaptive(UIColor(red: 0.98, green: 0.975, blue: 0.99, alpha: 1), UIColor(red: 0.055, green: 0.043, blue: 0.09, alpha: 1))
    static let surface = adaptive(.white, UIColor(red: 0.10, green: 0.085, blue: 0.15, alpha: 1))
    static let accent = adaptive(UIColor(red: 0.39, green: 0.28, blue: 0.67, alpha: 1), UIColor(red: 0.77, green: 0.68, blue: 0.96, alpha: 1))
    static let status = adaptive(UIColor(red: 0.13, green: 0.39, blue: 0.30, alpha: 1), UIColor(red: 0.72, green: 0.91, blue: 0.83, alpha: 1))
    static let onAccent = adaptive(.white, UIColor(red: 0.055, green: 0.043, blue: 0.09, alpha: 1))
    static let hero = adaptive(UIColor(red: 0.91, green: 0.87, blue: 0.97, alpha: 1), UIColor(red: 0.22, green: 0.17, blue: 0.33, alpha: 1))
}

struct AppearanceToggle: View {
    @AppStorage("appearance") private var appearance = "dark"
    var body: some View {
        Button { appearance = appearance == "dark" ? "light" : "dark" } label: {
            Image(systemName: appearance == "dark" ? "sun.max" : "moon")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.045), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance == "dark" ? "切换为白色背景" : "切换为深色背景")
        .accessibilityIdentifier("appearanceToggle")
        .accessibilityValue(appearance == "dark" ? "深色" : "浅色")
    }
}

@MainActor
final class AppIconStore: ObservableObject {
    static let names = ["GPT", "Claude", "DeepSeek", "Gemini", "Grok"]
    @Published private(set) var selected = UIApplication.shared.alternateIconName?.replacingOccurrences(of: "AppIcon", with: "") ?? "GPT"
    @Published private(set) var busy = false
    @Published var error: String?

    func select(_ name: String) {
        guard Self.names.contains(name), !busy, name != selected else { return }
        guard UIApplication.shared.supportsAlternateIcons else { error = "当前系统未开放更换图标。"; return }
        busy = true
        UIApplication.shared.setAlternateIconName(name == "GPT" ? nil : "AppIcon\(name)") { [weak self] failure in
            Task { @MainActor in
                self?.busy = false
                if let failure { self?.error = failure.localizedDescription }
                else { self?.selected = name }
            }
        }
    }
}

struct AppIconPicker: View {
    @StateObject private var icons = AppIconStore()
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("桌面图标").font(.system(size: 16, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 15) {
                ForEach(AppIconStore.names, id: \.self) { name in
                    Button { icons.select(name) } label: {
                        VStack(spacing: 6) {
                            Image("IconPreview\(name)").resizable().scaledToFit()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(icons.selected == name ? AppPalette.accent : .clear, lineWidth: 2))
                            Text(name).font(.system(size: 10))
                            if icons.selected == name {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(AppPalette.status)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 100, alignment: .top)
                    }
                    .buttonStyle(.plain).disabled(icons.busy)
                    .accessibilityLabel("\(name) 图标")
                    .accessibilityAddTraits(icons.selected == name ? .isSelected : [])
                }
            }
            if let error = icons.error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("更换图标不会更换陪伴角色。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.worldCard()
    }
}
