#if os(macOS)
import AppKit
import Testing
@testable import HighlightKit

/// Generates the README showcase images straight from the library —
/// no external tooling, what you see is what `attributedString(for:)`
/// produces. Gated behind an output directory:
///
///     HIGHLIGHTKIT_SCREENSHOTS=.github/assets swift test --filter Screenshot
@Suite("Screenshot generator")
struct ScreenshotGenerator {
    private static let samples: [(language: String, caption: String, code: String)] = [
        (
            "swift", "Swift — Xcode theme available too",
            """
            // TODO: ship it
            import HighlightKit

            struct CodeCard: View {
                @State private var source = "print(\\"hi\\")"

                var body: some View {
                    Text(AttributedString(Highlighter.shared.attributedString(
                        for: source, language: "swift", theme: .xcode
                    )))
                }
            }
            """
        ),
        (
            "javascript", "JavaScript — or pass nil and let detection pick",
            """
            const fib = (n, memo = new Map()) =>
              n <= 1 ? n : memo.get(n) ?? memo
                .set(n, fib(n - 1, memo) + fib(n - 2, memo))
                .get(n);
            export default { fib, version: 0x1F };
            """
        ),
        (
            "sql", "SQL — one of 64 bundled grammars",
            """
            SELECT name, COUNT(*) AS notes FROM blocks
              WHERE kind = 'code' GROUP BY name ORDER BY notes DESC;
            """
        ),
    ]

    @Test func generateShowcase() throws {
        guard let dir = ProcessInfo.processInfo.environment["HIGHLIGHTKIT_SCREENSHOTS"] else {
            return // opt-in only
        }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(theme: .githubLight, to: root.appendingPathComponent("showcase-light.png"))
        try write(theme: .githubDark, to: root.appendingPathComponent("showcase-dark.png"))
    }

    private func write(theme: HighlightTheme, to url: URL) throws {
        let contentWidth: CGFloat = 560
        let padding: CGFloat = 28
        let blockGap: CGFloat = 22

        let captionColor = theme.style(forScope: "comment")?.color ?? theme.foregroundColor
        let captionFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)

        // lay out all blocks first
        var blocks: [(caption: NSAttributedString, code: NSAttributedString, height: CGFloat)] = []
        for sample in Self.samples {
            let caption = NSAttributedString(string: sample.caption.uppercased(), attributes: [
                .font: captionFont,
                .foregroundColor: captionColor,
                .kern: 0.8,
            ])
            let code = Highlighter.shared.attributedString(
                for: sample.code, language: sample.language, theme: theme
            )
            let codeHeight = code.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin]
            ).height
            blocks.append((caption, code, ceil(codeHeight) + 22))
        }
        let totalHeight = padding * 2
            + blocks.reduce(0) { $0 + $1.height }
            + blockGap * CGFloat(blocks.count - 1)
        let size = CGSize(width: contentWidth + padding * 2, height: ceil(totalHeight))

        // 2× bitmap for crisp text
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        theme.backgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        var y = size.height - padding
        for block in blocks {
            y -= 14
            block.caption.draw(at: CGPoint(x: padding, y: y))
            y -= block.height - 14
            block.code.draw(
                with: NSRect(x: padding, y: y, width: contentWidth, height: block.height - 22),
                options: [.usesLineFragmentOrigin]
            )
            y -= blockGap
        }

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
        print("[screenshots] wrote \(url.path)")
    }
}
#endif
