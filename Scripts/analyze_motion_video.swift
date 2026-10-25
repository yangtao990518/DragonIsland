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
    for y in y0..<y1 {
        for x in x0..<x1 {
            let base = y * stride + x * 4
            pixels.append(pointer[base]); pixels.append(pointer[base + 1]); pixels.append(pointer[base + 2])
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    var difference = 0.0
    if let old = previous, old.count == pixels.count {
        difference = zip(old, pixels).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(pixels.count)
    }
    previous = pixels
    rows.append(["videoSeconds": timestamp, "sessionSecondsApprox": elapsed, "meanRGBChange": difference])
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
let result: [String: Any] = ["targetFPS": 30, "videoNominalFPS": track.nominalFrameRate, "decodedFrames": count, "selectedWalkingFrames": rows.count, "savedWalkingCrops": saved, "timingCaveat": "Session alignment uses host video-start time; recorder startup may offset it. Pixel differences include compression noise; this is not a physical-device FPS measurement.", "samples": rows]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("video-analysis.json"))
print("System-video verification: \(count) decoded frames; \(rows.count) walking-window samples; nominal \(track.nominalFrameRate)fps; target 30fps. Physical-device FPS is not verified.")
