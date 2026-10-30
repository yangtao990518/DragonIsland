import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

enum ChatMediaImport {
    static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 10 * 1024 * 1024 else { throw ChatMediaError.tooLarge }
        return try Data(contentsOf: url)
    }
}

/// Decode only the current frame at display size. Never materialize hundreds of GIF frames in memory.
private final class ChatGIFImageView: UIImageView {
    private var source: CGImageSource?
    private var delays: [Double] = []
    private var link: CADisplayLink?
    private var epoch: CFTimeInterval = 0
    private var current = -1
    private var identity: URL?
    private var reduced = false
    func configure(url: URL, reduceMotion: Bool) {
        guard identity != url || reduced != reduceMotion else { return }
        stop(); identity = url; reduced = reduceMotion; current = -1; delays = []; image = nil
        source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        guard let source else { return }
        for index in 0..<CGImageSourceGetCount(source) {
            let p = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            delays.append(max(0.02, (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1))
        }
        show(0); resume()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); window == nil ? stop() : resume() }
    func stop() { link?.invalidate(); link = nil }
    private func resume() {
        guard window != nil, link == nil, delays.count > 1, !reduced else { return }
        epoch = CACurrentMediaTime()
        let timer = CADisplayLink(target: self, selector: #selector(tick))
        timer.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
        timer.add(to: .main, forMode: .common); link = timer
    }
    @objc private func tick(_ timer: CADisplayLink) {
        let total = delays.reduce(0, +)
        guard total > 0 else { return }
        var time = (timer.timestamp - epoch).truncatingRemainder(dividingBy: total)
        for index in delays.indices { if time < delays[index] { show(index); return }; time -= delays[index] }
    }
    private func show(_ index: Int) {
        guard index != current, let source else { return }
        if let frame = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
            image = UIImage(cgImage: frame); current = index
        }
    }
}

private struct ChatAnimatedImage: UIViewRepresentable {
    let url: URL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeUIView(context: Context) -> ChatGIFImageView {
        let view = ChatGIFImageView(); view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateUIView(_ view: ChatGIFImageView, context: Context) { view.configure(url: url, reduceMotion: reduceMotion) }
    static func dismantleUIView(_ view: ChatGIFImageView, coordinator: ()) { view.stop() }
}

struct ChatAttachmentView: View {
    let attachment: ChatAttachment
    let media: ChatMediaFiles
    var maximum: CGFloat = 200
    @State private var enlarged = false
    var body: some View {
        Button { enlarged = true } label: {
            ChatAnimatedImage(url: media.url(for: attachment.asset))
                .aspectRatio(CGFloat(attachment.asset.width) / CGFloat(attachment.asset.height), contentMode: .fit)
                .frame(maxWidth: maximum, maxHeight: maximum)
                .clipShape(RoundedRectangle(cornerRadius: attachment.kind == .sticker ? 0 : 12))
        }.buttonStyle(.plain)
            .accessibilityLabel(attachment.description + (attachment.asset.animated ? "，动态 GIF" : ""))
            .accessibilityIdentifier(attachment.kind == .sticker ? "chatStickerAttachment" : "chatImageAttachment")
            .fullScreenCover(isPresented: $enlarged) {
                NavigationStack {
                    ChatAnimatedImage(url: media.url(for: attachment.asset)).padding()
                        .navigationTitle(attachment.kind == .sticker ? attachment.sticker?.name ?? "表情" : "图片")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { enlarged = false } } }
                }
            }
    }
}

struct CharacterStickerLibraryView: View {
    @ObservedObject var store: ChatStore
    let character: CompanionCharacter
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var candidate: Data?
    @State private var name = ""
    @State private var meaning = ""
    @State private var editing: CharacterSticker?
    @State private var loading = false
    var body: some View {
        Form {
            Section {
                PhotosPicker("从照片添加", selection: $photo, matching: .images).disabled(loading)
                    .accessibilityIdentifier("addStickerFromPhotos")
                Button("从文件添加 PNG / JPEG / GIF") { importing = true }.disabled(loading)
                if loading { ProgressView() }
            } footer: { Text("表情只属于\(character.name)。静态和 GIF 均可；名称、含义帮助 AI 选择合适表情。聊天图片与表情库分别管理。最多 100 个，单个 10 MB、GIF 最长 20 秒。") }
            if candidate != nil || editing != nil {
                Section(editing == nil ? "新表情" : "编辑表情") {
                    TextField("名称（最多 40 字）", text: $name).accessibilityIdentifier("stickerName")
                    TextField("表达什么情绪 / 适合什么情境（最多 300 字）", text: $meaning, axis: .vertical)
                        .accessibilityIdentifier("stickerMeaning")
                    Button("保存表情") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40 || meaning.count > 300)
                        .accessibilityIdentifier("saveCharacterSticker")
                    Button("取消编辑", role: .cancel) { candidate = nil; editing = nil }
                }
            }
            Section("\(character.name)的表情 · \(store.stickers(for: character.id).count)") {
                if store.stickers(for: character.id).isEmpty { Text("还没有表情，先添加一张吧。").foregroundStyle(.secondary) }
                ForEach(store.stickers(for: character.id)) { sticker in
                    HStack {
                        ChatAttachmentView(attachment: .init(id: sticker.id, kind: .sticker, asset: sticker.asset, sticker: sticker), media: store.media, maximum: 72)
                        VStack(alignment: .leading) {
                            Text(sticker.name)
                            Text(sticker.meaning).font(.caption).foregroundStyle(.secondary)
                            if sticker.asset.animated { Text("GIF · \(sticker.asset.frameCount) 帧").font(.caption2) }
                        }
                        Spacer()
                        Button("编辑") { candidate = nil; editing = sticker; name = sticker.name; meaning = sticker.meaning }
                            .buttonStyle(.borderless)
                    }.swipeActions { Button("移除", role: .destructive) { store.removeSticker(sticker.id) } }
                }
            }
            Section { Text("移除表情后，已经发送的消息仍保留。AI 自动发送需在该角色「AI 与人格」里开启。普通图片发送至接口时使用静态预览，GIF 的动画只在聊天中播放。")
                    .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("\(character.name)的表情包").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .gif]) { result in
                do { try prepare(ChatMediaImport.read(result.get())) } catch { store.error = error.localizedDescription }
            }
            .onChange(of: photo) { _, selection in
                guard let selection else { return }
                loading = true
                Task { @MainActor in
                    defer { loading = false; photo = nil }
                    do { guard let data = try await selection.loadTransferable(type: Data.self) else { throw ChatMediaError.invalid }; try prepare(data) }
                    catch { store.error = error.localizedDescription }
                }
            }
            .alert("表情包", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("知道了", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
    private func prepare(_ data: Data) throws { _ = try ChatMediaAsset.inspect(data); candidate = data; editing = nil; name = ""; meaning = "" }
    private func save() {
        let saved: Bool
        if let editing { saved = store.editSticker(editing.id, name: name, meaning: meaning) }
        else if let candidate { saved = store.addSticker(data: candidate, characterID: character.id, name: name, meaning: meaning) }
        else { return }
        if saved { candidate = nil; editing = nil; name = ""; meaning = "" }
    }
}

struct ChatStickerPicker: View {
    @ObservedObject var store: ChatStore
    let characterIDs: [String]
    let conversationID: UUID
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(characterIDs, id: \.self) { id in
                    if let character = store.character(id) {
                        Section(character.name) {
                            NavigationLink("管理\(character.name)的表情包") { CharacterStickerLibraryView(store: store, character: character) }
                            ForEach(store.stickers(for: id)) { sticker in
                                HStack {
                                    ChatAttachmentView(attachment: .init(id: sticker.id, kind: .sticker, asset: sticker.asset, sticker: sticker), media: store.media, maximum: 64)
                                    Text(sticker.name); Spacer()
                                    Button("选用") {
                                        if store.attach(.init(id: UUID(), kind: .sticker, asset: sticker.asset, sticker: sticker), in: conversationID) { dismiss() }
                                    }.buttonStyle(.bordered).accessibilityIdentifier("chooseSticker-\(sticker.name)")
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("表情包").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }
}
