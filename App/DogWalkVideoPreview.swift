import AVFoundation
import Combine
import SwiftUI
import UIKit

/// A real MP4 decoder for comparing with the same clip's image-sequence preview.
@MainActor
private final class DogWalkVideoPlayback: ObservableObject {
    let player = AVQueuePlayer()
    @Published var available = false
    @Published var status = "尚未加载视频"
    private var looper: AVPlayerLooper?
    private var observation: AnyCancellable?
    init() {
        guard let url = Bundle.main.url(forResource: "DafeiyuDogWalkTest", withExtension: "mp4") else { return }
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        available = true
        observation = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.status = value == .playing ? "正在播放" : value == .waitingToPlayAtSpecifiedRate ? "正在缓冲" : "已暂停"
            }
    }
    func setPlaying(_ active: Bool) {
        if active { player.play() } else { player.pause() }
    }
}

private struct DogWalkPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ uiView: Surface, context: Context) { uiView.playerLayer.player = player }
    static func dismantleUIView(_ uiView: Surface, coordinator: ()) { uiView.playerLayer.player = nil }
}

struct DogWalkVideoPreview: View {
    @StateObject private var playback = DogWalkVideoPlayback()
    @State private var visible = false
    @State private var manuallyPlaying = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var playing: Bool { visible && scenePhase == .active && (!reduceMotion || manuallyPlaying) }
    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - 12, 330)
            ZStack {
                if playback.available {
                    DogWalkPlayerSurface(player: playback.player)
                } else {
                    Text("视频资源未能加载，请重新打开角色页面。")
                        .font(.caption).foregroundStyle(.white)
                }
                if reduceMotion && !manuallyPlaying && playback.available {
                    Button("播放视频") { manuallyPlaying = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(width: width, height: width * 96 / 180)
            .background(.black).clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("dogWalkVideoStage")
        .accessibilityLabel("大肥鱼遛狗视频测试版")
        .accessibilityValue(playback.status)
        .onAppear { visible = true; playback.setPlaying(playing) }
        .onDisappear { visible = false; playback.setPlaying(false) }
        .onChange(of: playing) { _, value in playback.setPlaying(value) }
    }
}
