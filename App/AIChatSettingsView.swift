import SwiftUI
import UniformTypeIdentifiers

struct AIChatSettingsView: View {
    @ObservedObject var store: ChatStore
    let character: CompanionCharacter
    @Environment(\.dismiss) private var dismiss
    @State private var profile: AICharacterProfile
    @State private var user: AIUserProfile
    @State private var key = ""
    @State private var hasKey = false
    @State private var models = DeepSeekModel.defaults
    @State private var checking = false
    @State private var status: String?
    @State private var failure: String?
    @State private var reset = false
    private let credentials = AIChatCredentials()

    init(store: ChatStore, character: CompanionCharacter) {
        self.store = store; self.character = character
        _profile = State(initialValue: store.configuration.profile(for: character))
        _user = State(initialValue: store.configuration.user)
    }

    private var modelChoices: [DeepSeekModel] {
        models.contains(where: { $0.id == profile.model }) ? models : models + [.init(id: profile.model, name: nil)]
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("服务商", value: "DeepSeek 官方开放平台")
                Text(DeepSeekChatClient.baseURL.absoluteString).font(.caption).textSelection(.enabled)
                SecureField(hasKey ? "已保存，输入可替换密钥" : "输入 API Key", text: $key)
                    .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("deepseekKey")
                Button("保存密钥") { saveKey() }.disabled(key.isEmpty)
                    .accessibilityIdentifier("saveDeepseekKey")
                Button {
                    Task { await checkConnection() }
                } label: {
                    HStack { Text("检测连接并刷新模型"); if checking { ProgressView() } }
                }.disabled(checking).accessibilityIdentifier("checkDeepseekConnection")
                if hasKey { Button("移除密钥", role: .destructive) { removeKey() } }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("接口与密钥") } footer: {
                Text("所有角色共用此密钥，仅保存在这台手机的钥匙串。聊天会将本轮消息、选定的历史和人设发送至 DeepSeek。")
            }
            Section("\(character.name)的模型") {
                Picker("模型", selection: $profile.model) {
                    ForEach(modelChoices) { Text($0.title).tag($0.id) }
                }.accessibilityIdentifier("characterAIModel")
                Toggle("思考模式", isOn: $profile.thinking).accessibilityIdentifier("characterAIThinking")
                Stepper("携带最近 \(profile.contextRounds) 轮对话", value: $profile.contextRounds, in: 0...100)
                    .accessibilityIdentifier("characterContextRounds")
                Text("0 表示只发送本轮消息。完整聊天仍保存在手机，不会因上下文轮数变少而删除。群聊中的角色依次回复。")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("输出上限 \(profile.maxOutputTokens) tokens", value: $profile.maxOutputTokens, in: 128...32768, step: 512)
                Text("思考也占用输出额度；额度过小可能提前结束回复。调用费用由 DeepSeek 账户承担。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("允许 AI 发送专属表情", isOn: Binding(get: { profile.automaticStickers == true }, set: { profile.automaticStickers = $0 }))
                    .accessibilityIdentifier("characterAutomaticStickers")
                NavigationLink("管理\(character.name)的表情包") { CharacterStickerLibraryView(store: store, character: character) }
                Toggle("允许角色了解和操作 App", isOn: Binding(get: { profile.appControl == true }, set: { profile.appControl = $0 }))
                    .accessibilityIdentifier("characterAppControl")
            } header: { Text("\(character.name)的能力") } footer: {
                Text("表情仅从本角色库选择，每次回复最多一个。App 操作限本 App 的陪伴、展示图、场景、动作与闹钟；修改前会让你确认。关闭权限立即生效。发送图片时会将静态预览随消息提交给接口，需选择支持图片的模型。")
            }
            Section("\(character.name)的人格") {
                field("身份背景", text: $profile.background, id: "aiBackground")
                field("性格", text: $profile.personality, id: "aiPersonality")
                field("说话习惯", text: $profile.speakingStyle, id: "aiSpeakingStyle")
                field("喜好", text: $profile.interests, id: "aiInterests")
                field("与我的关系", text: $profile.relationship, id: "aiRelationship")
                field("如何称呼我", text: $profile.callsUser, id: "aiCallsUser")
                field("补充人设与要求", text: $profile.additionalInstructions, id: "aiInstructions")
                Button("恢复该角色默认设置", role: .destructive) { reset = true }
            }
            Section {
                TextField("我的昵称", text: $user.nickname).accessibilityIdentifier("aiUserNickname")
                field("想让角色了解的我", text: $user.information, id: "aiUserInformation")
                Toggle("向角色提供我的资料", isOn: $user.shareWithCharacters)
                    .accessibilityIdentifier("aiShareUserInfo")
            } header: { Text("我的资料 · 所有角色共用") } footer: {
                Text("关闭后，新的请求不再附加此处资料。已经发出的聊天内容不会因此撤回。")
            }
        }
        .navigationTitle("AI 与人格").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    var next = store.configuration
                    next.characters[character.id] = profile; next.user = user
                    do {
                        try next.validate()
                        if !key.isEmpty {
                            try credentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                            key = ""; hasKey = true
                        }
                    } catch { failure = error.localizedDescription; return }
                    if store.saveConfiguration(next) { dismiss() } else { failure = store.error; store.error = nil }
                }.accessibilityIdentifier("saveAISettings")
            }
        }
        .onAppear {
            do { hasKey = try credentials.readKey() != nil } catch { failure = error.localizedDescription }
        }
        .confirmationDialog("恢复模型、上下文和人格为默认值？保存后生效。", isPresented: $reset, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) { profile = .standard(for: character) }
        }
        .alert("AI 配置", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("知道了", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text, axis: .vertical).lineLimit(2...6).accessibilityIdentifier(id)
        }
    }
    private func saveKey() {
        do {
            try credentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
            key = ""; hasKey = true; status = "密钥已保存在本机。"
        } catch { failure = error.localizedDescription }
    }
    private func removeKey() {
        do { try credentials.delete(); hasKey = false; key = ""; status = "密钥已移除。" }
        catch { failure = error.localizedDescription }
    }
    @MainActor private func checkConnection() async {
        checking = true; status = nil
        defer { checking = false }
        do {
            let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = candidate.isEmpty ? try credentials.readKey() : candidate else { throw AIChatError.missingKey }
            models = try await DeepSeekChatClient().models(key: value)
            status = "连接成功，已读取 \(models.count) 个模型。\(candidate.isEmpty ? "" : "新密钥尚未保存，请点保存密钥。")"
        } catch { failure = error.localizedDescription }
    }
}

struct ChatBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw AIChatError.backupVersion }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ChatBackupView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var document = ChatBackupDocument(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: Data?
    @State private var status: String?
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Text("聊天记录、群组、草稿、角色人格、模型选择和我的资料保存在此 App 的本地目录。卸载 App 会删除这些数据，请先导出备份。")
                Text("备份包含聊天图片、静态及 GIF 表情原文件；不含 API 密钥、角色动作、闹钟或其他 App 设置。聊天目录不参与系统备份，请使用此处导出保存。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("导出本地备份") {
                    do { document = ChatBackupDocument(data: try store.exportBackup()); exporting = true }
                    catch { failure = error.localizedDescription }
                }.accessibilityIdentifier("exportChatBackup").disabled(!store.ready || !store.replyingIDs.isEmpty)
                Button("从文件恢复备份") { importing = true }
                    .accessibilityIdentifier("importChatBackup").disabled(!store.replyingIDs.isEmpty)
                Text("可存到“文件 → 我的 iPhone”，再复制到电脑。单份备份上限 20 MB（含媒体），超过后会提示，不能导出缺图备份。恢复会替换当前全部聊天与人格设置；现有密钥保留。卸载前请把备份移到 App 目录之外。")
                    .font(.caption).foregroundStyle(.secondary)
                if let status { Text(status).font(.caption) }
            }
        }.navigationTitle("本地备份").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "mAIverse-chat-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
                switch result {
                case .success: status = "备份已导出。请妥善保管，其中含有聊天和个人资料。"
                case .failure: failure = "备份导出未完成，请重试。"
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= ChatBackup.maximumSize else { throw AIChatError.backupTooLarge }
                    let data = try Data(contentsOf: url)
                    _ = try ChatBackup.decode(data)
                    pending = data
                } catch let error as AIChatError { failure = error.localizedDescription }
                catch { failure = "无法读取有效的 mAIverse 备份，原有数据未修改。" }
            }
            .confirmationDialog("用此备份替换全部聊天和人格设置？建议先导出当前备份。", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                    Button("恢复并替换", role: .destructive) {
                        if let pending {
                            if store.importBackup(pending) { status = "备份已恢复。" }
                            else { failure = store.error; store.error = nil }
                        }
                        pending = nil
                    }
                }
            .alert("本地备份", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("知道了", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
    }
}
