import Foundation
import CoreText

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "ttf" }
guard urls.count == 32 else { fatalError("Missing unread avatar fonts") }
for url in urls {
    var error: Unmanaged<CFError>?
    guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { fatalError("Cannot register \(url.lastPathComponent)") }
    let name = url.deletingPathExtension().lastPathComponent
    let font = CTFontCreateWithName(name as CFString, 24, nil)
    for sample in ["1:00", "59:07", "1:24:36", "7:59:59"] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var all: [CGGlyph] = []
        for run in runs {
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs); all += glyphs
        }
        let expected = CTFontGetGlyphWithName(font, ("f" + String(sample.suffix(2))) as CFString)
        guard expected != 0, all.last == expected else { fatalError("Timer shaping failed: \(name) \(sample)") }
    }
}
print("Unread avatar CoreText shaping verified: 32 fonts, both identities, minute/hour formats.")
