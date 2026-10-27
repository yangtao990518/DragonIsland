import Foundation
import CoreText

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let prefixes = ["black": "mAIverse", "meadow": "mAIverseMeadow", "night": "mAIverseNight"]
struct Check: Decodable { let fontPrefix: String?; let scene: String; let bank: Int; let phase: Int; let second: Int; let glyph: Int }
let tests = try JSONDecoder().decode([Check].self, from: Data(contentsOf: directory.appendingPathComponent("checks.json")))
for prefix in Set(tests.map { $0.fontPrefix ?? prefixes[$0.scene]! }) {
 for phase in 0..<60 {
    let url = directory.appendingPathComponent("\(prefix)F\(phase).ttf")
    var error: Unmanaged<CFError>?
    guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
        fatalError("Motion font registration failed: \(String(describing: error))")
    }
 }
}
for test in tests {
    let name = "\(test.fontPrefix ?? prefixes[test.scene]!)F\(test.phase)"
    let font = CTFontCreateWithName(name as CFString, 32, nil)
    let value = test.bank == 0 ? String(format: "1:%02d", test.second) : String(format: "%d:01:%02d", test.bank * 3, test.second)
    let text = NSAttributedString(string: value, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let runs = CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text as CFAttributedString)) as! [CTRun]
    var actual: [CGGlyph] = []
    for run in runs {
        var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        actual += glyphs
    }
    guard actual.last == CGGlyph(test.glyph) else {
        fatalError("CoreText variation/ligature mismatch: \(test), actual \(actual)")
    }
}
print("CoreText shaped all \(tests.count) scene/bank/phase cases with the expected glyphs.")

