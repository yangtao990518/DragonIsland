import SwiftUI

struct IslandScenePicker: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("岛上小世界").font(.system(size: 17, weight: .semibold))
            Text("为她挑一片喜欢的风景。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 9) {
                ForEach(IslandScene.allCases) { scene in
                    Button { Task { await store.setIslandScene(scene) } } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Image(scene.asset).resizable().scaledToFill()
                                DragonPortrait(character: store.displayCharacter, size: 43)
                            }
                            .frame(height: 58).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            Text(scene.title).font(.system(size: 11, weight: .medium))
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Image(systemName: store.islandScene == scene ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15)).foregroundStyle(AppPalette.accent)
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("islandScene-\(scene.rawValue)")
                    .accessibilityLabel(scene.title)
                    .accessibilityValue(store.islandScene == scene ? "已选择" : "未选择")
                }
            }.disabled(store.busy)
            Text("场景装饰人物活动区和展开内容，系统的黑色外框会保留。选择会保存，也会应用到当前陪伴。")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }.worldCard()
    }
}
