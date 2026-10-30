import SwiftUI
import UIKit
import ImageIO

/// Bounded decoding ahead of the display clock. Never holds all 240 decoded images.
private final class HomeSceneDecoder {
    private let queue = DispatchQueue(label: "world.home-scene.decode", qos: .userInitiated)
    private let cache = NSCache<NSNumber, UIImage>()
    private var pending = Set<Int>() // main-thread access only
    private let clip: HomeSceneAnimation
    private var generation = UUID()

    init(clip: HomeSceneAnimation) {
        self.clip = clip
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 6
    }

    func clear() { generation = UUID(); cache.removeAllObjects(); pending.removeAll() }

    func image(at index: Int) -> UIImage? { cache.object(forKey: NSNumber(value: index)) }

    func request(_ index: Int, ready: @escaping (Int, UIImage) -> Void) {
        guard clip.frameNames.indices.contains(index), image(at: index) == nil,
              pending.insert(index).inserted else { return }
        let name = clip.frameNames[index], ticket = generation
        queue.async { [weak self] in
            let decoded: UIImage? = autoreleasepool {
                guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0,
                          [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
                return UIImage(cgImage: image)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == ticket else { return }
                self.pending.remove(index)
                guard let decoded else { return }
                self.cache.setObject(decoded, forKey: NSNumber(value: index),
                    cost: (decoded.cgImage?.bytesPerRow ?? 0) * (decoded.cgImage?.height ?? 0))
                ready(index, decoded)
            }
        }
    }
}

struct HomeScenePlayer: UIViewRepresentable {
    let clip: HomeSceneAnimation
    let visible: Bool
    let replay: Int
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(clip: clip) }
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "homeScenePlayback"
        view.accessibilityLabel = "大肥鱼窗边触屏完整抽帧动画"
        context.coordinator.view = view
        context.coordinator.show(0)
        return view
    }
    func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.configure(active: visible && scenePhase == .active, reduceMotion: reduceMotion, replay: replay)
    }
    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) { coordinator.dispose() }

    final class Coordinator: NSObject {
        weak var view: UIImageView?
        private let clip: HomeSceneAnimation
        private let decoder: HomeSceneDecoder
        private var link: CADisplayLink?
        private var epoch: CFTimeInterval = 0
        private var elapsed: TimeInterval = 0
        private var active = false
        private var reduced = false
        private var manual = false
        private var completed = false
        private var token = 0
        private var wanted = 0
        private var displayed = -1

        init(clip: HomeSceneAnimation) { self.clip = clip; decoder = HomeSceneDecoder(clip: clip) }

        func configure(active: Bool, reduceMotion: Bool, replay: Int) {
            if replay != token {
                pause(); token = replay; elapsed = 0; manual = true; completed = false
                show(0)
            }
            self.active = active; reduced = reduceMotion
            if !active || (reduced && !manual) { pause() }
            else if !completed && link == nil {
                epoch = CACurrentMediaTime() - elapsed
                let timer = CADisplayLink(target: self, selector: #selector(tick))
                timer.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                timer.add(to: .main, forMode: .common); link = timer
            }
            updateAccessibility()
        }

        private func pause() {
            if link != nil { elapsed = max(0, CACurrentMediaTime() - epoch) }
            link?.invalidate(); link = nil
        }

        func dispose() { pause(); decoder.clear() }

        @objc private func tick(_ timer: CADisplayLink) {
            elapsed = max(0, timer.timestamp - epoch)
            show(clip.frameIndex(elapsed: elapsed))
            if elapsed * 1000 >= clip.durationMs {
                completed = true; pause(); elapsed = clip.durationMs / 1000
                updateAccessibility()
            }
        }

        func show(_ index: Int) {
            wanted = index
            if let image = decoder.image(at: index), displayed != index {
                view?.image = image; displayed = index
            }
            for next in index..<min(clip.frameCount, index + 4) {
                decoder.request(next) { [weak self] decodedIndex, image in
                    guard let self, self.wanted == decodedIndex else { return }
                    self.view?.image = image; self.displayed = decodedIndex
                }
            }
        }

        private func updateAccessibility() {
            view?.accessibilityValue = completed ? "播放完成" : link == nil ? "已暂停" : "正在播放"
        }
    }
}
