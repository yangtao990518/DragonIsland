// Inspect actual SpringBoard video, not an in-app animation mockup.
import Foundation
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let video = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("motion-capture.json"))) as! [String: Any]
let epoch = metadata["epoch"] as! Double
let videoStart = Double(try String(contentsOf: folder.appendingPathComponent("video-start-unix.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
let asset = AVURLAsset(url: video)
let track = asset.tracks(withMediaType: .video).first!
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(output)
reader.startReading()
let context = CIContext()
var previous: [UInt8]?
var rows: [[String: Any]] = []
var saved = 0
var count = 0
var firstPTS: Double?
var lastPTS = 0.0
var minElapsed = Double.greatestFiniteMagnitude
var maxElapsed = -Double.greatestFiniteMagnitude
var visibleByMinute: [Int: Int] = [:]
while let sample = output.copyNextSampleBuffer() {
    count += 1
    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    if firstPTS == nil { firstPTS = pts }
    lastPTS = pts
    // simctl/AVAssetWriter may retain a nonzero media time origin. Normalize
    // presentation timestamps before combining them with host wall-clock time.
    let timestamp = pts - firstPTS!
    let elapsed = timestamp + videoStart - epoch
    minElapsed = min(minElapsed, elapsed); maxElapsed = max(maxElapsed, elapsed)
    guard elapsed >= 7, elapsed < 158, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    // Plan 6: first right walk at 15s, left at 30s, repeated every minute.
    // A 0.2s margin tolerates the recorder startup offset. Keep full burst and
    // neighboring idle so that compression noise can be compared with motion.
    let phase = elapsed.truncatingRemainder(dividingBy: 60)
    guard (14.7...17.0).contains(phase) || (29.7...32.0).contains(phase) else { continue }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let height = CVPixelBufferGetHeight(buffer)
    let width = CVPixelBufferGetWidth(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    // Excludes the countdown and clock. Coordinates use the 1206x2622 capture.
    let x0 = Int(Double(width) * 300 / 1206), x1 = Int(Double(width) * 435 / 1206)
    let y0 = Int(Double(height) * 40 / 2622), y1 = Int(Double(height) * 150 / 2622)
    var pixels: [UInt8] = []
    var visiblePixels = 0
    var minCharacterX = x1, maxCharacterX = x0
    var minCharacterY = y1, maxCharacterY = y0
    for y in y0..<y1 {
        for x in x0..<x1 {
            let base = y * stride + x * 4
            pixels.append(pointer[base]); pixels.append(pointer[base + 1]); pixels.append(pointer[base + 2])
            let b = Int(pointer[base]), g = Int(pointer[base + 1]), r = Int(pointer[base + 2])
            if min(r, g, b) > 100, r >= g - 3, b >= r - 5 {
                visiblePixels += 1
                minCharacterX = min(minCharacterX, x); maxCharacterX = max(maxCharacterX, x)
                minCharacterY = min(minCharacterY, y); maxCharacterY = max(maxCharacterY, y)
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    var difference = 0.0
    if let old = previous, old.count == pixels.count {
        difference = zip(old, pixels).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(pixels.count)
    }
    previous = pixels
    rows.append(["videoSeconds": timestamp, "sessionSecondsApprox": elapsed, "meanRGBChange": difference,
                 "characterPixels": visiblePixels, "characterCenterX": Double(minCharacterX + maxCharacterX) / 2,
                 "characterWidth": max(0, maxCharacterX - minCharacterX + 1),
                 "characterHeight": max(0, maxCharacterY - minCharacterY + 1)])
    let minute = Int(elapsed / 60)
    visibleByMinute[minute] = max(visibleByMinute[minute] ?? 0, visiblePixels)
    if saved < 360, (15.0...16.8).contains(phase) || (30.0...31.8).contains(phase) {
        let image = CIImage(cvPixelBuffer: buffer)
        let rect = CGRect(x: CGFloat(x0), y: CGFloat(height - y1), width: CGFloat(x1 - x0), height: CGFloat(y1 - y0))
        if let cg = context.createCGImage(image, from: rect) {
            let file = folder.appendingPathComponent(String(format: "walk-video-%03d.png", saved))
            if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, cg, nil); CGImageDestinationFinalize(destination)
            }
        }
        saved += 1
    }
}
guard reader.status == .completed else { fatalError("Video decoding failed: \(String(describing: reader.error))") }
let timing: [String: Any] = ["decodedFrames": count, "firstPTS": firstPTS ?? -1, "lastPTS": lastPTS, "videoStartUnix": videoStart, "sessionEpochUnix": epoch, "minSessionElapsed": minElapsed, "maxSessionElapsed": maxElapsed, "selectedFrames": rows.count, "savedCrops": saved]
try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("video-timing.json"))
print("Video timing diagnostics: \(timing)")
guard !rows.isEmpty, saved > 0 else { throw NSError(domain: "SystemMotionQA", code: 1, userInfo: [NSLocalizedDescriptionKey: "No walking-window samples; inspect video-timing.json and the saved system video."]) }
guard (0..<3).allSatisfy({ (visibleByMinute[$0] ?? 0) > 200 }) else {
    throw NSError(domain: "SystemMotionQA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Character not visible in every sampled minute: \(visibleByMinute)"])
}
let result: [String: Any] = ["targetFPS": 30, "videoNominalFPS": track.nominalFrameRate, "decodedFrames": count, "selectedWalkingFrames": rows.count, "savedWalkingCrops": saved, "timingCaveat": "Session alignment uses host video-start time; recorder startup may offset it. Pixel differences include compression noise; this is not a physical-device FPS measurement.", "samples": rows]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("video-analysis.json"))
// Build 8's video had a narrow front-facing pose briefly jump sideways between
// two adjacent side-walk poses. Reject that same observed defect independently
// of approximate session/video alignment, using only neighboring screen frames.
let changed = rows.filter { ($0["meanRGBChange"] as! Double) > 1 && ($0["characterPixels"] as! Int) > 200 }
var poseJumps: [[String: Any]] = []
if changed.count >= 3 {
    for i in 1..<(changed.count - 1) {
        let a = changed[i - 1], b = changed[i], c = changed[i + 1]
        let ta = a["videoSeconds"] as! Double, tb = b["videoSeconds"] as! Double, tc = c["videoSeconds"] as! Double
        let xa = a["characterCenterX"] as! Double, xb = b["characterCenterX"] as! Double, xc = c["characterCenterX"] as! Double
        let wa = a["characterWidth"] as! Int, wb = b["characterWidth"] as! Int, wc = c["characterWidth"] as! Int
        if tb - ta < 0.12, tc - tb < 0.12, abs(xa - xc) < 4,
           abs(xb - (xa + xc) / 2) > 8, Double(wb) < 0.9 * Double(min(wa, wc)) {
            poseJumps.append(["previous": a, "unexpected": b, "next": c])
        }
    }
}
try JSONSerialization.data(withJSONObject: ["isolatedPoseJumps": poseJumps, "changedSamples": changed.count], options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("pose-continuity.json"))
guard poseJumps.isEmpty else {
    throw NSError(domain: "SystemMotionQA", code: 3, userInfo: [NSLocalizedDescriptionKey: "Isolated pose jump in actual walking video; inspect pose-continuity.json and raw video."])
}
print("System-video verification: \(count) decoded frames; \(rows.count) walking-window samples; nominal \(track.nominalFrameRate)fps; target 30fps. Physical-device FPS is not verified.")
