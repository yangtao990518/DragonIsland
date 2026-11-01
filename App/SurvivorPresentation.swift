import SwiftUI
import AVFoundation

@MainActor final class GameOrientationDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.mask }
    static func setGame(_ enabled: Bool) {
        mask = enabled ? .landscape : .portrait
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations:mask))
        }
    }
}

/// Small resident audio pool; no file access or player allocation on each hit.
@MainActor final class SurvivorAudio {
    private var music: AVAudioPlayer?
    private var sounds: [String:[AVAudioPlayer]] = [:]
    private var nextSound = 0.0
    init() {
        guard let folder=Bundle.main.resourceURL?.appendingPathComponent("SurvivorGameV2/Audio") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default,options:[.mixWithOthers])
        music=try? AVAudioPlayer(contentsOf:folder.appendingPathComponent("music.wav"))
        music?.numberOfLoops = -1; music?.volume=0.3; music?.prepareToPlay()
        for name in ["cast","hit","heal","upgrade"] {
            sounds[name]=(0..<2).compactMap { _ in
                guard let p=try? AVAudioPlayer(contentsOf:folder.appendingPathComponent(name+".wav")) else { return nil }
                p.volume=0.22; p.prepareToPlay(); return p
            }
        }
    }
    func update(running: Bool) {
        if running && !UserDefaults.standard.bool(forKey:"survivorMusicMuted") { music?.play() }
        else { music?.pause(); sounds.values.flatMap{$0}.forEach{$0.stop()} }
    }
    func play(_ name:String, time:Double) {
        guard !UserDefaults.standard.bool(forKey:"survivorEffectsMuted"), time>=nextSound,
              let player=sounds[name]?.first(where:{!$0.isPlaying}) else { return }
        nextSound=time+0.12; player.currentTime=0; player.play()
    }
    func reset() { nextSound=0 }
    func stop() { music?.stop(); sounds.values.flatMap{$0}.forEach{$0.stop()} }
}
