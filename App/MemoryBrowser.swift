import SwiftUI

private func memorySize(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

struct LocalChatFileStats: Sendable {
    var bytes = 0
    var files = 0
    static func scan(_ url: URL) -> Self {
        var result = Self()
        guard let enumerator = FileManager.default.enumerator(at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return result }
        for case let item as URL in enumerator {
            guard let info = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            if info.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if info.isRegularFile == true { result.bytes += info.fileSize ?? 0; result.files += 1 }
        }
        return result
    }
}

struct MemoryBrowser: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var media = LocalChatFileStats()
    @State private var folders: [String: LocalChatFileStats] = [:]
    private var historyBytes: Int { (try? store.historyFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    var body: some View {
        List {
            Section {
                Text("长期记忆是角色独立的真实 Markdown 文件；聊天记录、人设和待确认记忆仍在原来的 history.json 中。")
                    .font(.subheadline)
                Text("聊天默认携带最近 \(store.characters.first.map { store.configuration.profile(for: $0).contextRounds } ?? 10) 轮，具体轮数以各角色设置为准；长期记忆会单独读取。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("角色记忆文件夹") {
                ForEach(store.characters) { character in
                    NavigationLink {
                        CharacterMemoryFolder(store: store, character: character)
                    } label: {
                        HStack(spacing: 12) {
                            CharacterAvatar(character: character, size: 38)
                            VStack(alignment: .leading, spacing: 4) {
                                Label(character.name, systemImage: "folder.fill")
                                Text("Memory/\(character.id)/").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(memorySize(folders[character.id]?.bytes ?? 0)).font(.caption)
                                Text("\(folders[character.id]?.files ?? 0) 个文件").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.accessibilityIdentifier("memoryFolder-\(character.id)")
                }
            }
            Section("现有上下文数据") {
                NavigationLink { StoredChatFilesView(store: store) } label: {
                    HStack {
                        Label("聊天记录与上下文", systemImage: "doc.text")
                        Spacer()
                        Text(memorySize(historyBytes)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("实际文件：Application Support/Chat/history.json\n共 \(store.conversations.count) 个会话。可进入编辑消息或删除记录；不直接修改内部 JSON，避免破坏附件和回复关联。")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("其他本机文件") {
                LabeledContent("图片与表情缓存", value: memorySize(media.bytes))
                Text("Media/ · \(media.files) 个文件。它们是聊天附件，不是长期记忆。密钥保存在钥匙串，本页不显示密钥。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("记忆会随聊天备份一起导出。清空聊天也不会删除已保存的长期记忆。删除长期记忆不会删除聊天记录或人设；若也不希望旧对话进入上下文，请另行编辑或清空相关聊天。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("AI 记忆与本机文件").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: store.memoryRevision) {
                let root = store.historyFileURL.deletingLastPathComponent()
                let roles = store.characters.map(\.id)
                let result = await Task.detached(priority: .utility) {
                    let media = LocalChatFileStats.scan(root.appendingPathComponent("Media"))
                    let folders = Dictionary(uniqueKeysWithValues: roles.map { ($0, LocalChatFileStats.scan(root.appendingPathComponent("Memory").appendingPathComponent($0))) })
                    return (media, folders)
                }.value
                if !Task.isCancelled { media = result.0; folders = result.1 }
            }
    }
}

private struct MemoryEditorItem: Identifiable {
    let document: CharacterMemoryDocument
    var suggestion: MemorySuggestion? = nil
    var id: UUID { document.id }
}

struct CharacterMemoryFolder: View {
    @ObservedObject var store: ChatStore
    let character: CompanionCharacter
    @State private var documents: [CharacterMemoryDocument] = []
    @State private var failure: String?
    @State private var editing: MemoryEditorItem?
    @State private var deleting: CharacterMemoryDocument?
    @State private var clearing = false
    private var automation: MemoryAutomationRole { store.memoryAutomation(for: character.id) }
    private var preparing: Bool { store.preparingMemoryRoles.contains(character.id) }
    private var sourceConversations: [ChatConversation] {
        store.conversations.filter { chat in chat.characterIDs.contains(character.id) && chat.messages.contains(where: {
            $0.isUser && $0.delivery == .sent && $0.replyCharacterIDs.contains(character.id) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) }
    }
    var body: some View {
        List {
            Section {
                Toggle("自动从新聊天整理记忆", isOn: Binding(get: { automation.enabled }, set: { _ = store.setAutomaticMemory($0, for: character.id) }))
                    .disabled(preparing).accessibilityIdentifier("automaticMemory-\(character.id)")
                Text("开启后，每 5 轮已完成的新文字对话整理一次，最多取最近 12 条用户消息。使用她现有 AI 接口，会消耗额度；结果仅进入待确认区，确认前不参与聊天。")
                    .font(.caption).foregroundStyle(.secondary)
                Menu("整理已有聊天（AI）") {
                    ForEach(sourceConversations) { chat in
                        Button(chat.title(in: store.characters)) { prepare(chat.id) }
                    }
                }.disabled(preparing || sourceConversations.isEmpty)
                if sourceConversations.isEmpty { Text("有已完成的用户文字消息后，才能从旧聊天整理记忆。").font(.caption).foregroundStyle(.secondary) }
                if preparing { ProgressView("正在整理，尚未写入长期记忆…") }
                if let attempt = automation.attempt, attempt.status == .failed {
                    Text(attempt.failure ?? "整理未完成").font(.caption).foregroundStyle(.secondary)
                    Button("重试上次整理") { prepare(attempt.conversationID, sourceIDs: attempt.messageIDs) }.disabled(preparing)
                }
                if let attempt = automation.attempt, attempt.status == .completed {
                    Text((attempt.generatedCount ?? 0) == 0 ? "最近一次整理完成，没有新的稳定事实需要保存。" : "最近一次整理完成，生成了 \(attempt.generatedCount ?? 0) 条待确认候选。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("自动整理 · 默认关闭") } footer: {
                Text("开启时不会自动上传整个旧聊天档案。已有内容可通过上方菜单主动整理；失败不会反复自动重试扣费。")
            }
            if !automation.suggestions.isEmpty {
                Section("待确认 · \(automation.suggestions.count) 条") {
                    ForEach(automation.suggestions) { suggestion in
                        Button {
                            editing = .init(document: .init(id: suggestion.id, characterID: character.id,
                                title: suggestion.title, text: suggestion.text, modifiedAt: .now), suggestion: suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(suggestion.title, systemImage: "sparkles").foregroundStyle(Color.primary)
                                Text(suggestion.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text("来源：\(suggestion.sourceQuote)").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.swipeActions { Button("丢弃", role: .destructive) { _ = store.discardMemorySuggestion(suggestion) } }
                    }
                }
            }
            Section {
                if documents.isEmpty { Text("还没有长期记忆文件").foregroundStyle(.secondary) }
                ForEach(documents) { document in
                    Button { editing = .init(document: document) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").foregroundStyle(AppPalette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title).foregroundStyle(Color.primary)
                                Text(document.filename).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(memorySize(document.byteCount)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.swipeActions { Button("删除", role: .destructive) { deleting = document } }
                }
                if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
                Button("新建记忆文件", systemImage: "doc.badge.plus") {
                    editing = .init(document: .init(id: UUID(), characterID: character.id, title: "", text: "", modifiedAt: .now))
                }.accessibilityIdentifier("newMemory-\(character.id)")
            } header: { Text("已保存 · \(documents.count) 个文件 · \(memorySize(documents.reduce(0) { $0 + $1.byteCount }))") } footer: {
                Text("真实位置：Application Support/Chat/Memory/\(character.id)/\n每条最多6000字、24 KB；每个角色合计12000字。保存后的内容会用于该角色后续聊天和主动开场，其他角色不会读取。")
            }
            Section {
                NavigationLink("查看她参与的聊天上下文") { StoredChatFilesView(store: store, characterID: character.id) }
                NavigationLink("人设与模型设置") { AIChatSettingsView(store: store, character: character) }
                Button("清空她的记忆文件夹", role: .destructive) { clearing = true }
            }
        }.navigationTitle("\(character.name)的记忆").navigationBarTitleDisplayMode(.inline)
            .task(id: store.memoryRevision) { load() }
            .sheet(item: $editing) { item in NavigationStack { CharacterMemoryEditor(store: store, item: item) } }
            .confirmationDialog("删除这条长期记忆？聊天记录仍会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除记忆文件", role: .destructive) { if let deleting { _ = store.deleteMemory(deleting) }; deleting = nil }
            }
            .confirmationDialog("清空\(character.name)的全部长期记忆文件？此操作无法撤销。", isPresented: $clearing, titleVisibility: .visible) {
                Button("清空记忆文件夹", role: .destructive) { _ = store.clearMemories(for: character.id) }
            }
            .alert("记忆管理", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("知道了") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
    private func load() {
        do { documents = try store.memoryFiles.documents(for: character.id); failure = nil }
        catch { documents = []; failure = error.localizedDescription }
    }
    private func prepare(_ conversationID: UUID, sourceIDs: [UUID]? = nil) {
        Task {
            do { try await store.prepareMemory(role: character.id, conversationID: conversationID, sourceIDs: sourceIDs) }
            catch { store.error = error.localizedDescription }
        }
    }
}

private struct CharacterMemoryEditor: View {
    @ObservedObject var store: ChatStore
    let item: MemoryEditorItem
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var failure: String?
    @State private var deleting = false
    init(store: ChatStore, item: MemoryEditorItem) {
        self.store = store; self.item = item
        _title = State(initialValue: item.document.title); _text = State(initialValue: item.document.text)
    }
    private var document: CharacterMemoryDocument {
        .init(id: item.document.id, characterID: item.document.characterID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), text: text, modifiedAt: .now)
    }
    var body: some View {
        Form {
            Section("记忆文件") {
                TextField("标题", text: $title).accessibilityIdentifier("memoryTitle")
                TextEditor(text: $text).frame(minHeight: 240).accessibilityIdentifier("memoryText")
                Text("\(text.count)/6000 字 · 保存后 \(memorySize(document.byteCount))").font(.caption).foregroundStyle(.secondary)
            }
            if let suggestion = item.suggestion {
                Section("AI 整理候选 · 核对原话后保存") {
                    Text(suggestion.sourceQuote).textSelection(.enabled)
                    Text("来源会话：\(store.conversation(suggestion.conversationID)?.title(in: store.characters) ?? "已删除")").font(.caption).foregroundStyle(.secondary)
                    Button("丢弃候选", role: .destructive) { if store.discardMemorySuggestion(suggestion) { dismiss() } }
                }
            } else if !item.document.title.isEmpty {
                Section { Button("删除这个记忆文件", role: .destructive) { deleting = true } }
            }
            Section {
                Text("Memory/\(document.characterID)/\(document.filename)").font(.caption2).textSelection(.enabled)
                Text("保存后会随该角色后续聊天发给其所用 AI 服务。删除文件不等于删除旧聊天中的相同内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(item.suggestion == nil ? "编辑记忆文件" : "确认长期记忆").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved: Bool
                        if let suggestion = item.suggestion { saved = store.confirmMemorySuggestion(suggestion, title: document.title, text: document.text) }
                        else { saved = store.saveMemory(document) }
                        if saved { dismiss() } else { failure = store.error; store.error = nil }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 80 || text.count > 6000 || document.byteCount > 24*1024)
                        .accessibilityIdentifier("saveMemory")
                }
            }
            .alert("记忆文件", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("知道了") { failure = nil }
            } message: { Text(failure ?? "") }
            .confirmationDialog("删除这个长期记忆文件？聊天记录仍保留。", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除记忆文件", role: .destructive) {
                    if store.deleteMemory(item.document) { dismiss() }
                    else { failure = store.error; store.error = nil }
                }
            }
    }
}

struct StoredChatFilesView: View {
    @ObservedObject var store: ChatStore
    var characterID: String? = nil
    private var chats: [ChatConversation] { store.conversations.filter { characterID == nil || $0.characterIDs.contains(characterID!) } }
    var body: some View {
        List {
            Section {
                Text("会话实际合存在 history.json，下列大小为该会话内容的编码大小。编辑后影响后续上下文；不会伪装成重新发送过消息。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(chats) { chat in
                NavigationLink { StoredConversationView(store: store, id: chat.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(chat.title(in: store.characters))
                            Text("\(chat.messages.count) 条消息 · \(chat.kind == .group ? "群聊" : "单聊")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(memorySize((try? JSONEncoder().encode(chat).count) ?? 0)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("聊天记录与上下文").navigationBarTitleDisplayMode(.inline)
    }
}

private struct StoredConversationView: View {
    @ObservedObject var store: ChatStore
    let id: UUID
    @State private var editing: ChatMessage?
    @State private var clearing = false
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            ForEach(store.conversation(id)?.messages ?? []) { message in
                Button { editing = message } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(message.senderName).font(.caption.weight(.semibold)); Spacer(); Text(message.createdAt, style: .time).font(.caption2) }
                        Text(message.text.isEmpty ? (message.attachments ?? []).map(\.description).joined(separator: " ") : message.text)
                            .font(.subheadline).lineLimit(4)
                    }.foregroundStyle(Color.primary)
                }
            }
        }.navigationTitle(store.conversation(id)?.title(in: store.characters) ?? "会话").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("清空消息", role: .destructive) { clearing = true }
                    Button("删除会话", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            } }
            .sheet(item: $editing) { message in NavigationStack { StoredMessageEditor(store: store, conversationID: id, message: message) } }
            .confirmationDialog("清空这个会话的全部消息？已保存的长期记忆仍保留。", isPresented: $clearing) { Button("清空", role: .destructive) { _ = store.clear(id) } }
            .confirmationDialog("删除这个会话？", isPresented: $deleting) { Button("删除", role: .destructive) { store.delete(id); if store.conversation(id) == nil { dismiss() } } }
            .alert("聊天文件", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("知道了") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

private struct StoredMessageEditor: View {
    @ObservedObject var store: ChatStore
    let conversationID: UUID
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var deleting = false
    @State private var failure: String?
    init(store: ChatStore, conversationID: UUID, message: ChatMessage) {
        self.store = store; self.conversationID = conversationID; self.message = message
        _text = State(initialValue: message.text)
    }
    var body: some View {
        Form {
            Section(message.senderName) {
                TextEditor(text: $text).frame(minHeight: 280)
                Text("只编辑已存文本；附件和消息关联保留。不会重新调用 AI。").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("删除这条消息", role: .destructive) { deleting = true } }
        }.navigationTitle("编辑聊天上下文").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    if store.editStoredMessage(message.id, in: conversationID, text: text) { dismiss() }
                    else { failure = store.error; store.error = nil }
                } }
            }
            .confirmationDialog("删除这条消息？删除用户消息会同时移除其关联回复。", isPresented: $deleting) {
                Button("删除", role: .destructive) {
                    if store.deleteStoredMessage(message.id, in: conversationID) { dismiss() }
                    else { failure = store.error; store.error = nil }
                }
            }
            .alert("聊天上下文", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("知道了") { failure = nil }
            } message: { Text(failure ?? "") }
    }
}
