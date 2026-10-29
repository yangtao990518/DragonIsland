import SwiftUI
import UIKit
import ImageIO

enum VideoActionFrames {
    static let clips = FullVideoAction.load()
    private static let queue = DispatchQueue(label: "world.video-action.atlas", qos: .userInitiated)
    static let atlases: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.totalCostLimit = 64 * 1024 * 1024; cache.countLimit = 3
        return cache
    }()
    private static func atlas(_ clip: FullVideoAction, page: Int) -> UIImage? {
        guard clip.atlases.indices.contains(page) else { return nil }
        let name = clip.atlases[page]
        let image: UIImage
        if let cached = atlases.object(forKey: name as NSString) { image = cached }
        else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            image = UIImage(cgImage: cg)
            atlases.setObject(image, forKey: name as NSString, cost: cg.bytesPerRow * cg.height)
        }
        return image
    }
    static func image(_ clip: FullVideoAction, index: Int) -> UIImage? {
        let cells = clip.grid[0] * clip.grid[1], page = index / cells, cell = index % cells
        guard let image = atlas(clip, page: page) else { return nil }
        if cell < 2 && clip.atlases.indices.contains(page + 1) {
            queue.async { _ = atlas(clip, page: page + 1) }
        }
        let w = clip.cellSize[0], h = clip.cellSize[1]
        let rect = CGRect(x: CGFloat(cell % clip.grid[0] * w), y: CGFloat(cell / clip.grid[0] * h), width: CGFloat(w), height: CGFloat(h))
        guard let cropped = image.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

struct FullVideoActionPreview: View {
    let characterID: String
    let action: String
    @State private var began = Date()
    @State private var pausedElapsed: TimeInterval = 0
    @State private var manuallyPlaying = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var clip: FullVideoAction? { VideoActionFrames.clips.first { $0.characterID == characterID && $0.action == action } }

    var body: some View {
        Group {
            if let clip {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished || scenePhase != .active || (reduceMotion && !manuallyPlaying))) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(began))
                    let completed = elapsed * 1000 >= clip.durationMs
                    VStack(spacing: 8) {
                        ZStack {
                            Color(red: 25/255, green: 32/255, blue: 51/255)
                            if let image = VideoActionFrames.image(clip, index: clip.frameIndex(elapsed: reduceMotion && !manuallyPlaying ? pausedElapsed : elapsed)) {
                                Image(uiImage: image).resizable().scaledToFit().padding(8)
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("fullVideoActionStage")
                            .accessibilityLabel("\(clip.title)完整抽帧预览")
                            .accessibilityValue(reduceMotion && !manuallyPlaying ? "已暂停" : completed ? "播放完成" : "正在播放")
                        HStack {
                            Text("完整片段 · \(String(format: "%.2f", clip.durationMs / 1000)) 秒").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(reduceMotion && !manuallyPlaying ? "播放" : "重播") { began = Date(); pausedElapsed = 0; manuallyPlaying = true; finished = false }
                                .font(.caption).accessibilityIdentifier("replayFullVideoAction")
                        }
                    }
                    .onChange(of: completed) { _, value in if value && (!reduceMotion || manuallyPlaying) { finished = true } }
                }
            } else { Text("动作资源暂不可用").foregroundStyle(.secondary) }
        }
        .onChange(of: action) { _, _ in began = Date(); pausedElapsed = 0; manuallyPlaying = false; finished = false }
        .onChange(of: scenePhase) { previous, current in
            if previous == .active && (!reduceMotion || manuallyPlaying) { pausedElapsed = Date().timeIntervalSince(began) }
            if current == .active { began = Date().addingTimeInterval(-pausedElapsed) }
        }
    }
}
