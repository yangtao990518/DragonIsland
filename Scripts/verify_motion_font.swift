import Foundation
import CoreText

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let url = directory.appendingPathComponent("mAIverseMotion.ttf")
var error: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
    fatalError("Motion font registration failed: \(String(describing: error))")
}
let tests = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("checks.json"))) as! [[String: Int]]
for test in tests {
    let name = "mAIverseB\(test["bank"]!)P\(test["phase"]!)"
    let font = CTFontCreateWithName(name as CFString, 32, nil)
    let text = NSAttributedString(string: String(format: "%02d", test["second"]!), attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let runs = CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text as CFAttributedString)) as! [CTRun]
    var actual: [CGGlyph] = []
    for run in runs {
        var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        actual += glyphs
    }
    guard actual == [CGGlyph(test["glyph"]!)] else {
        fatalError("CoreText variation/ligature mismatch: \(test), actual \(actual)")
    }
}
print("CoreText shaped all \(tests.count) bank/phase cases with the expected variable glyphs.")
