import SwiftUI

struct PixelFXLibraryView: View {
    @ObservedObject var game: SurvivorGameController
    let upgrading: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var archive = false
    @State private var query = ""
    @State private var category = "all"
    @State private var selected: PixelFXSkill?
    @State private var notice: String?
    private var categories: [String] { Array(Set(game.skills.map(\.category))).sorted() }
    private var filtered: [PixelFXSkill] {
        game.skills.filter { skill in
            (archive || skill.selectable) && (category == "all" || skill.category == category) &&
            (query.isEmpty || "\(skill.id) \(skill.title) \(skill.categoryTitle) \(skill.profile.title)".localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text(upgrading ? "选择本次升级技能 · 已装备\(game.battle.equippedPixelSkills.count)/6" : "选择初始技能 · 所有技能均会自动释放")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Toggle("查看物品与展示特效（不可装备）",isOn:$archive).font(.caption)
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack {
                            categoryButton("全部 \(game.skills.count)",id:"all")
                            ForEach(categories,id:\.self) { id in categoryButton(game.skills.first { $0.category == id }?.categoryTitle ?? id,id:id) }
                        }
                    }
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                        ForEach(filtered) { skill in
                            Button { selected = skill } label: {
                                VStack(alignment:.leading,spacing:10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius:15).fill(.white.opacity(0.04))
                                        if let image = game.thumbnail(skill.id) { Image(uiImage:image).resizable().interpolation(.none).scaledToFit().padding(10) }
                                    }.frame(height:108)
                                    Text(skill.title).font(.subheadline.bold()).lineLimit(2).frame(height:36,alignment:.topLeading)
                                    HStack {
                                        Text(skill.roleTitle).font(.caption2).foregroundStyle(.secondary)
                                        Spacer(minLength:0)
                                        if game.starterID == skill.id && !upgrading { Image(systemName:"checkmark.circle.fill").foregroundStyle(.cyan) }
                                        if upgrading && game.battle.rank(skill.upgrade)>0 { Text("Lv.\(game.battle.rank(skill.upgrade))").font(.caption2).foregroundStyle(.cyan) }
                                    }
                                }.padding(12).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:21))
                            }.buttonStyle(.plain).accessibilityIdentifier("pixelFXSkill_\(skill.id)")
                        }
                    }
                    Text("PixelFX · Patch / Hugo Duprez · MIT").font(.caption2).foregroundStyle(.secondary)
                    Link("来源与版权说明",destination:URL(string:"https://github.com/patch-gg/pixelfx")!).font(.caption)
                }.padding(20)
            }
            .background(Color(red:0.06,green:0.1,blue:0.18))
            .navigationTitle("PixelFX 技能库")
            .searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"搜索技能名称、类型")
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(item:$selected) { skill in
                PixelFXSkillDetail(game:game,skill:skill,upgrading:upgrading) {
                    if upgrading {
                        if game.chooseLibrarySkill(skill.id) { selected=nil; dismiss() }
                        else { notice="本局最多6项技能，每项最高5级。已满时请强化现有技能。" }
                    } else { game.selectStarter(skill.id); selected=nil; dismiss() }
                }
            }
            .alert("技能选择",isPresented:Binding(get:{notice != nil},set:{if !$0 {notice=nil}})) {
                Button("知道了") { notice=nil }
            } message: { Text(notice ?? "") }
        }.preferredColorScheme(.dark)
    }
    private func categoryButton(_ title: String,id: String) -> some View {
        Button { category=id } label: { Text(title).font(.caption.bold()).padding(.horizontal,14).padding(.vertical,10)
            .background(category==id ? Color.indigo : .white.opacity(0.07),in:Capsule())
        }.buttonStyle(.plain)
    }
}

private struct PixelFXSkillDetail: View {
    @ObservedObject var game: SurvivorGameController
    let skill: PixelFXSkill
    let upgrading: Bool
    let choose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var started = Date()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    TimelineView(.animation(minimumInterval:1.0/30,paused:phase != .active)) { context in
                        ZStack {
                            RoundedRectangle(cornerRadius:24).fill(Color(red:0.09,green:0.15,blue:0.2))
                            if let image = game.preview(skill.id,time:context.date.timeIntervalSince(started)) {
                                Image(uiImage:image).resizable().interpolation(.none).scaledToFit().padding(16)
                            }
                        }.frame(height:280)
                    }.accessibilityIdentifier("pixelFXLivePreview")
                    Text(skill.title).font(.title.bold())
                    HStack { Text(skill.categoryTitle); Text("·"); Text(skill.roleTitle) }.font(.subheadline).foregroundStyle(.cyan)
                    Text(skill.description).font(.subheadline).foregroundStyle(.secondary)
                    Text(skill.selectable ? skill.stats(at:1)+"\n最高5级，选择前可查看每一级变化。" : "此项不进入战斗技能池。")
                        .font(.subheadline).lineSpacing(5)
                    if skill.selectable {
                        ForEach(1...5,id:\.self) { level in Text("\(level)级："+skill.stats(at:level)).font(.caption).foregroundStyle(.secondary) }
                    }
                    Button(action:choose) {
                        Text(upgrading ? "选择本次强化" : "设为初始技能").font(.headline).frame(maxWidth:.infinity).padding(18)
                            .background(.indigo,in:RoundedRectangle(cornerRadius:18))
                    }.buttonStyle(.plain).accessibilityIdentifier("pixelFXChooseSkill")
                        .disabled(!skill.selectable || upgrading && (game.battle.rank(skill.upgrade)>=5 || (game.battle.rank(skill.upgrade)==0 && game.battle.equippedPixelSkills.count>=6)))
                }.padding(24)
            }.navigationTitle("技能预览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("返回") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
