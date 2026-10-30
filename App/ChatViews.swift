import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private enum NewChatSheet: String, Identifiable {
    case direct, group
    var id: String { rawValue }
}

struct ChatPage: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var tools: ChatAppTools
    @State private var path: [UUID] = []
    @State private var sheet: NewChatSheet?
    @State private var pendingID: UUID?
    @State private var search = ""
    @State private var deleting: ChatConversation?
    @State private var showingBackup = false
    @State private var configuring: CompanionCharacter?

    private var filtered: [ChatConversation] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.conversations.filter {
            term.isEmpty || $0.title(in: store.characters).localizedCaseInsensitiveContains(term)
                || $0.messages.last?.text.localizedCaseInsensitiveContains(term) == true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.title2).foregroundStyle(AppPalette.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("想说的话，都可以留在这里。雨天晴天，随时见面。")
                                .font(.subheadline)
                            Text("配置 DeepSeek 后即可聊天，记录保存在本机。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }.listRowBackground(AppPalette.surface)

                if !store.ready {
                    Section {
                        ContentUnavailableView("聊天记录暂不可用", systemImage: "externaldrive.badge.exclamationmark",
                                               description: Text("原记录已保留，请重试读取。"))
                        Button("重新读取") { store.reload() }
                    }
                } else if store.conversations.isEmpty {
                    Section {
                        ContentUnavailableView("第一句话，从这里开始", systemImage: "bubble.left",
                                               description: Text("选择角色单独聊天，或邀请她们加入群组。"))
                        Button { sheet = .direct } label: { Label("和角色聊天", systemImage: "square.and.pencil") }
                            .accessibilityIdentifier("startDirectChat")
                        Button { sheet = .group } label: { Label("创建群组", systemImage: "person.3") }
                            .accessibilityIdentifier("startGroupChat")
                    }.listRowBackground(AppPalette.surface)
                } else {
                    Section("会话") {
                        ForEach(filtered) { conversation in
                            NavigationLink(value: conversation.id) {
                                ChatConversationRow(conversation: conversation, store: store)
                            }
                            .accessibilityIdentifier("chat-\(conversation.id)")
                            .swipeActions {
                                Button("删除", role: .destructive) { deleting = conversation }
                            }
                        }
                        if filtered.isEmpty { Text("没有找到这段聊天").foregroundStyle(.secondary) }
                    }.listRowBackground(AppPalette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .searchable(text: $search, prompt: "搜索角色、群组或最近消息")
            .navigationTitle("聊天")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(store.characters) { character in
                            Button("\(character.name) · AI 与人格") { configuring = character }
                        }
                        Button("本地备份", systemImage: "externaldrive") { showingBackup = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("聊天设置").accessibilityIdentifier("chatPreferences")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("和角色聊天", systemImage: "person.crop.circle.badge.plus") { sheet = .direct }
                        Button("创建群组", systemImage: "person.3") { sheet = .group }
                    } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("新建聊天").accessibilityIdentifier("newChat")
                    .disabled(!store.ready)
                }
            }
            .navigationDestination(for: UUID.self) { id in ChatRoom(store: store, id: id) }
        }
        .sheet(item: $sheet, onDismiss: {
            if let id = pendingID { path.append(id); pendingID = nil }
        }) { selection in
            ChatEditor(store: store, kind: selection == .direct ? .direct : .group) { id in
                pendingID = id
            }
        }
        .sheet(item: $tools.approval, onDismiss: { tools.resolve(false) }) { approval in
            ChatAppApprovalView(tools: tools, approval: approval)
        }
        .sheet(isPresented: $showingBackup) { NavigationStack { ChatBackupView(store: store) } }
        .sheet(item: $configuring) { character in NavigationStack { AIChatSettingsView(store: store, character: character) } }
        .confirmationDialog("删除这段聊天及全部记录？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("删除聊天", role: .destructive) {
                if let deleting { store.delete(deleting.id) }
                deleting = nil
            }
        }
        .alert("聊天", isPresented: Binding(
            get: { store.error != nil }, set: { if !$0 { store.error = nil } }
        )) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

private struct ChatConversationRow: View {
    let conversation: ChatConversation
    @ObservedObject var store: ChatStore

    var body: some View {
        HStack(spacing: 12) {
            ChatAvatar(character: store.character(conversation.characterIDs.first), group: conversation.kind == .group)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(conversation.title(in: store.characters)).font(.headline).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conversation.updatedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if conversation.kind == .group {
                        Text("群组 · \(conversation.characterIDs.count + 1) 人").foregroundStyle(AppPalette.accent)
                    }
                    Text(preview).foregroundStyle(.secondary).lineLimit(1)
                }.font(.caption)
            }
        }.padding(.vertical, 7)
    }

    private var preview: String {
        if store.replyingIDs.contains(conversation.id) { return "正在回复…" }
        if !conversation.draft.isEmpty { return "[草稿] \(conversation.draft)" }
        guard let message = conversation.messages.last else { return "还没有消息，打个招呼吧" }
        return "\(message.senderName)：\(message.text.isEmpty ? (message.attachments ?? []).map(\.description).joined(separator: " ") : message.text)"
    }
}

private struct ChatEditor: View {
    @ObservedObject var store: ChatStore
    let kind: ChatKind
    let existingID: UUID?
    let onSave: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selected: Set<String>
    @State private var search = ""
    @State private var error: String?

    init(store: ChatStore, kind: ChatKind, existing: ChatConversation? = nil, onSave: @escaping (UUID) -> Void) {
        self.store = store
        self.kind = kind
        self.existingID = existing?.id
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _selected = State(initialValue: Set(existing?.characterIDs ?? []))
    }

    private var availableSelection: [String] { store.characters.map(\.id).filter(selected.contains) }
    private var canSave: Bool {
        !availableSelection.isEmpty && (kind == .direct || (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 30))
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .group {
                    Section("群组名称") {
                        TextField("给群组起个名字", text: $name)
                            .accessibilityIdentifier("chatGroupName")
                        Text("\(name.count)/30").font(.caption).foregroundStyle(name.count > 30 ? .red : .secondary)
                    }
                }
                Section(
                    header: Text(kind == .direct ? "选择聊天角色" : "选择群成员 · 已选 \(availableSelection.count) 位角色"),
                    footer: Text(kind == .direct ? "同一角色会继续已有的单聊。" : "你会自动加入群组。至少选择一位角色，之后可随时添加或移除成员。")
                ) {
                    ForEach(store.characters.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { character in
                        Button {
                            if kind == .direct { selected = [character.id] }
                            else if selected.contains(character.id) { selected.remove(character.id) }
                            else { selected.insert(character.id) }
                        } label: {
                            HStack(spacing: 12) {
                                ChatAvatar(character: character)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name).foregroundStyle(Color.primary)
                                    Text(character.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(character.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(AppPalette.accent)
                            }.padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("chatSelect-\(character.id)")
                        .accessibilityValue(selected.contains(character.id) ? "已选择" : "未选择")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background(AppPalette.background)
            .searchable(text: $search, prompt: "搜索角色")
            .navigationTitle(existingID != nil ? "管理群组" : kind == .group ? "创建群组" : "和角色聊天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingID != nil ? "保存" : "开始聊天") { save() }
                        .disabled(!canSave || !store.ready)
                        .accessibilityIdentifier("saveChat")
                }
            }
        }
    }

    private func save() {
        if let existingID {
            guard store.editGroup(existingID, name: name, characterIDs: availableSelection) else {
                error = store.error; store.error = nil; return
            }
            onSave(existingID)
        } else {
            guard let id = store.create(kind: kind, name: name, characterIDs: availableSelection) else {
                error = store.error; store.error = nil; return
            }
            onSave(id)
        }
        dismiss()
    }
}

private struct ChatRoom: View {
    @ObservedObject var store: ChatStore
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var photo: PhotosPickerItem?
    @State private var importingImage = false
    @State private var choosingSticker = false
    @State private var importing = false
    @State private var editingGroup = false
    @State private var confirmingClear = false
    @State private var confirmingDelete = false
    @FocusState private var composing: Bool

    private var chat: ChatConversation? { store.conversation(id) }
    private var replying: Bool { store.replyingIDs.contains(id) }
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if let chat {
                VStack(spacing: 0) {
                    if chat.kind == .group { members(chat) }
                    messages(chat)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .navigationTitle(chat.title(in: store.characters))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if chat.kind == .group {
                                Button("管理群组", systemImage: "person.3") { editingGroup = true }.disabled(replying)
                            }
                            Button(role: .destructive) { confirmingClear = true } label: {
                                Label("清空聊天记录", systemImage: "eraser")
                            }.disabled(replying)
                            Button(role: .destructive) { confirmingDelete = true } label: {
                                Label("删除聊天", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("聊天设置").accessibilityIdentifier("chatSettings")
                    }
                }
            } else {
                ContentUnavailableView("聊天已删除", systemImage: "bubble.left")
            }
        }
        .background(AppPalette.background)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { draft = chat?.draft ?? "" }
        .onDisappear { if chat != nil { store.setDraft(draft, in: id) } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, chat != nil { store.setDraft(draft, in: id) }
        }
        .fileImporter(isPresented: $importingImage, allowedContentTypes: [.png, .jpeg, .gif]) { result in
            do { store.attach(data: try ChatMediaImport.read(result.get()), in: id) } catch { store.error = error.localizedDescription }
        }
        .sheet(isPresented: $choosingSticker) { ChatStickerPicker(store: store, characterIDs: chat?.characterIDs ?? [], conversationID: id) }
        .onChange(of: photo) { _, selection in
            guard let selection else { return }
            importing = true
            Task { @MainActor in
                defer { importing = false; photo = nil }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw ChatMediaError.invalid }
                    store.attach(data: data, in: id)
                } catch { store.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $editingGroup) {
            if let chat { ChatEditor(store: store, kind: .group, existing: chat) { _ in } }
        }
        .confirmationDialog("清空聊天记录？此操作无法撤销。", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空记录", role: .destructive) { if store.clear(id) { draft = "" } }
        }
        .confirmationDialog("删除这段聊天及全部记录？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除聊天", role: .destructive) {
                store.delete(id)
                if chat == nil { dismiss() }
            }
        }
    }

    private func members(_ chat: ChatConversation) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Label("我", systemImage: "person.crop.circle")
                ForEach(chat.characterIDs, id: \.self) { member in
                    HStack(spacing: 3) {
                        ChatAvatar(character: store.character(member), size: 24)
                        Text(store.character(member)?.name ?? "暂不可用")
                    }
                }
            }.font(.caption).padding(.horizontal, 16).padding(.vertical, 9)
        }.background(AppPalette.surface)
    }

    private func messages(_ chat: ChatConversation) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 18) {
                    Text("记录保存在本机 · AI 回复可能存在错误")
                        .font(.caption2).foregroundStyle(.secondary).padding(.vertical, 12)
                    if chat.messages.isEmpty {
                        ContentUnavailableView("打个招呼吧", systemImage: "hand.wave",
                                               description: Text(chat.kind == .group ? "这里是你们的小群组。" : "今天有什么想分享的？"))
                    }
                    ForEach(chat.messages) { message in
                        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 7) {
                            ChatMessageRow(message: message, character: store.character(message.characterID), media: store.media)
                            if message.isUser && message.delivery == .failed {
                                Button { store.retry(in: id, messageID: message.id) } label: {
                                    Label("回复未完成，点击重试", systemImage: "arrow.clockwise")
                                }
                                .font(.caption).disabled(replying)
                                .accessibilityIdentifier("retryChat-\(message.id)")
                            }
                        }
                    }
                    if replying {
                        if let partial = store.streaming[id], !partial.text.isEmpty {
                            HStack(alignment: .top, spacing: 9) {
                                ChatAvatar(character: store.character(partial.characterID), size: 36)
                                Text(partial.text).font(.system(size: 16)).textSelection(.enabled)
                                    .padding(14).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18))
                                Spacer(minLength: 40)
                            }.accessibilityIdentifier("streamingChatReply")
                        }
                        HStack(spacing: 8) {
                            ProgressView(); Text("正在回复…").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("停止") { store.stop(id) }.font(.caption).accessibilityIdentifier("stopChatReply")
                        }
                            .accessibilityIdentifier("chatReplying")
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scroll.scrollTo("chat-bottom", anchor: .bottom) }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onChange(of: composing) { _, focused in
                if focused { withAnimation { scroll.scrollTo("chat-bottom", anchor: .bottom) } }
            }
            .onChange(of: store.streaming[id]?.text) { _, _ in
                if !composing { scroll.scrollTo("chat-bottom", anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if !(chat?.draftAttachments ?? []).isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(chat?.draftAttachments ?? []) { item in
                            VStack {
                                ChatAttachmentView(attachment: item, media: store.media, maximum: 70)
                                Button("移除") { store.detach(item.id, in: id) }.font(.caption).disabled(replying)
                            }
                        }
                    }
                }
            }
            HStack {
                PhotosPicker(selection: $photo, matching: .images) { Label("图片", systemImage: "photo") }
                    .accessibilityIdentifier("chatAddImage")
                Button("文件", systemImage: "folder") { importingImage = true }.accessibilityIdentifier("chatImageFromFiles")
                Button("表情", systemImage: "face.smiling") { choosingSticker = true }.accessibilityIdentifier("chatOpenStickers")
                Spacer()
                if importing { ProgressView() }
            }.font(.caption).disabled(replying || importing || !store.ready)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("说点什么…", text: $draft, axis: .vertical)
                    .lineLimit(1...5).focused($composing)
                    .padding(12).background(AppPalette.background, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("chatInput")
                Button {
                    if store.send(draft, in: id) { draft = "" }
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(AppPalette.accent)
                .foregroundStyle(AppPalette.onAccent)
                .disabled((trimmed.isEmpty && (chat?.draftAttachments ?? []).isEmpty) || trimmed.count > 4000 || replying || importing || !store.ready)
                .accessibilityLabel("发送").accessibilityIdentifier("sendChat")
            }
            if draft.count > 3600 {
                Text("\(draft.count)/4000").font(.caption2)
                    .foregroundStyle(draft.count > 4000 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(AppPalette.surface)
    }
}

private struct ChatAvatar: View {
    var character: CompanionCharacter?
    var group = false
    var user = false
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(AppPalette.accent.opacity(0.10))
            if let character, !group, !user {
                CharacterAvatar(character: character, size: size - 6)
            } else {
                Image(systemName: group ? "person.3.fill" : user ? "person.fill" : "person.crop.circle.badge.questionmark")
                    .font(.system(size: size * 0.40)).foregroundStyle(AppPalette.accent)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let character: CompanionCharacter?
    let media: ChatMediaFiles

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if message.isUser { Spacer(minLength: 40) }
            else { ChatAvatar(character: character, size: 36) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
                Text(message.isUser ? "我" : character?.name ?? message.senderName)
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(message.attachments ?? []) { item in
                    ChatAttachmentView(attachment: item, media: media, maximum: item.kind == .sticker ? 150 : 220)
                }
                if !message.text.isEmpty { Text(message.text)
                    .font(.system(size: 16)).textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .foregroundStyle(message.isUser ? AppPalette.onAccent : Color.primary)
                    .background(message.isUser ? AppPalette.accent : AppPalette.surface,
                                in: RoundedRectangle(cornerRadius: 18))
                    .contextMenu { Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text } } }
                Text(message.createdAt, style: .time).font(.system(size: 10)).foregroundStyle(.secondary)
                if message.interrupted == true { Text("回复未完成").font(.caption2).foregroundStyle(.secondary) }
            }
            if message.isUser { ChatAvatar(user: true, size: 36) }
            else { Spacer(minLength: 40) }
        }.accessibilityElement(children: .contain)
    }
}
