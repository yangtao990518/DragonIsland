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
let walkStarts = Array((metadata["walkingSlots"] as? [Int] ?? [15, 30]).filter { $0 >= 10 && $0 <= 50 }.prefix(2))
let rollStarts = Array((metadata["rollingSlots"] as? [Int] ?? []).prefix(2))
let walkDuration = metadata["walkingDuration"] as? Int ?? 5
let rollDuration = metadata["rollingDuration"] as? Int ?? 5
let windows = walkStarts.map { (action: "walk", start: $0, duration: walkDuration) }
    + rollStarts.map { (action: "roll", start: $0, duration: rollDuration) }
guard walkStarts.count == 2 else { fatalError("QA plan must include an outward and return walking leg") }
guard rollStarts.count == 2 else { fatalError("QA plan must include an outward and return rolling leg") }
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
    guard elapsed >= 7, elapsed < 178, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    // Inspect both complete actions; rolling must move on the actual island.
    let phase = elapsed.truncatingRemainder(dividingBy: 60)
    guard windows.contains(where: { window in
        let lower = Double(window.start) - 0.5
        let upper = Double(window.start + window.duration) + 0.5
        return (lower...upper).contains(phase)
    }) else { continue }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let height = CVPixelBufferGetHeight(buffer)
    let width = CVPixelBufferGetWidth(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    // Excludes the countdown and clock. Coordinates use the 1206x2622 capture.
    let x0 = Int(Double(width) * 180 / 1206), x1 = Int(Double(width) * 500 / 1206)
    let y0 = Int(Double(height) * 40 / 2622), y1 = Int(Double(height) * 160 / 2622)
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
    // The clock can intrude when no Live Activity is rendered. It is much shorter
    // than the character; reject that false positive before counting visibility.
    if maxCharacterY - minCharacterY + 1 < Int(Double(height) * 50 / 2622) {
        visiblePixels = 0
    }
    var difference = 0.0
    if let old = previous, old.count == pixels.count {
        difference = zip(old, pixels).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(135 * 110 * 3)
    }
    previous = pixels
    let currentAction = windows.first { Double($0.start) <= phase && phase < Double($0.start + $0.duration) }?.action ?? "transition"
    var row: [String: Any] = ["videoSeconds": timestamp, "sessionSecondsApprox": elapsed, "meanRGBChange": difference, "motionAction": currentAction,
                 "characterPixels": visiblePixels, "characterCenterX": Double(minCharacterX + maxCharacterX) / 2,
                 "characterWidth": max(0, maxCharacterX - minCharacterX + 1),
                 "characterHeight": max(0, maxCharacterY - minCharacterY + 1)]
    let minute = Int(elapsed / 60)
    visibleByMinute[minute] = max(visibleByMinute[minute] ?? 0, visiblePixels)
    if saved < 1500, difference > 1, visiblePixels > 200 {
        let image = CIImage(cvPixelBuffer: buffer)
        let rect = CGRect(x: CGFloat(x0), y: CGFloat(height - y1), width: CGFloat(x1 - x0), height: CGFloat(y1 - y0))
        if let cg = context.createCGImage(image, from: rect) {
            let name = String(format: "walk-video-%03d.png", saved)
            let file = folder.appendingPathComponent(name)
            if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, cg, nil); CGImageDestinationFinalize(destination)
                row["cropFile"] = name
            }
        }
        saved += 1
    }
    rows.append(row)
}
guard reader.status == .completed else { fatalError("Video decoding failed: \(String(describing: reader.error))") }
let timing: [String: Any] = ["decodedFrames": count, "firstPTS": firstPTS ?? -1, "lastPTS": lastPTS, "videoStartUnix": videoStart, "sessionEpochUnix": epoch, "minSessionElapsed": minElapsed, "maxSessionElapsed": maxElapsed, "selectedFrames": rows.count, "savedCrops": saved]
try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("video-timing.json"))
print("Video timing diagnostics: \(timing)")
guard !rows.isEmpty, saved > 0 else { throw NSError(domain: "SystemMotionQA", code: 1, userInfo: [NSLocalizedDescriptionKey: "No walking-window samples; inspect video-timing.json and the saved system video."]) }
guard (0..<3).allSatisfy({ (visibleByMinute[$0] ?? 0) > 200 }) else {
    throw NSError(domain: "SystemMotionQA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Character not visible in every sampled minute: \(visibleByMinute)"])
}
let result: [String: Any] = ["targetFPS": 30, "videoNominalFPS": track.nominalFrameRate, "decodedFrames": count, "selectedWalkingFrames": rows.count, "savedWalkingCrops": saved, "walkingLegStarts": walkStarts, "timingCaveat": "Session alignment uses host video-start time; recorder startup may offset it. Pixel differences include compression noise, normalized to the former ROI area; this is not a physical-device FPS measurement.", "samples": rows]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("video-analysis.json"))
// Build 8's video had a narrow front-facing pose briefly jump sideways between
// two adjacent side-walk poses. Reject that same observed defect independently
// of approximate session/video alignment, using only neighboring screen frames.
let changed = rows.filter { ($0["motionAction"] as? String) == "walk" && ($0["meanRGBChange"] as! Double) > 1 && ($0["characterPixels"] as! Int) > 200 }
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
var travel: [[String: Any]] = []
for minute in 0..<3 {
    for window in windows {
        let low = Double(minute * 60 + window.start) - 0.5
        let high = Double(minute * 60 + window.start + window.duration) + 0.5
        let centers = rows.filter { ($0["sessionSecondsApprox"] as! Double) >= low && ($0["sessionSecondsApprox"] as! Double) <= high && ($0["characterPixels"] as! Int) > 200 }.map { $0["characterCenterX"] as! Double }
        let extent = (centers.max() ?? 0) - (centers.min() ?? 0)
        let isRight = window.start == (window.action == "walk" ? walkStarts.first : rollStarts.first)
        let signedTravel = ((centers.last ?? 0) - (centers.first ?? 0)) * (isRight ? 1 : -1)
        travel.append(["minute": minute, "action": window.action, "direction": isRight ? "right" : "left", "slotStart": window.start,
                       "duration": window.duration, "screenTravelPixels": extent, "signedTravelPixels": signedTravel, "samples": centers.count])
    }
}
try JSONSerialization.data(withJSONObject: travel, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("motion-travel.json"))
guard travel.allSatisfy({ ($0["screenTravelPixels"] as! Double) >= 70 && ($0["signedTravelPixels"] as! Double) >= 60 }) else {
    throw NSError(domain: "SystemMotionQA", code: 4, userInfo: [NSLocalizedDescriptionKey: "Character must walk AND roll across the stage in both directions; inspect motion-travel.json."])
}
print("System-video verification: \(count) decoded frames; \(rows.count) walking-window samples; nominal \(track.nominalFrameRate)fps; target 30fps. Physical-device FPS is not verified.")

