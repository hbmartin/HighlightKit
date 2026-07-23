public import Foundation

public enum HighlightedDocumentError: Error, Equatable, Sendable {
    case invalidUTF16Range(NSRange)
}

/// A selected, self-contained document view. Token ranges are UTF-16 ranges
/// rebased to `text` (the first selected unit is zero); `sourceRange` records
/// the corresponding range in the complete document.
public struct HighlightedDocumentSnapshot: Sendable {
    public let language: String?
    public let sourceRange: NSRange
    public let text: String
    public let tokens: [HighlightToken]
    public let omittedTokenCount: Int
    public var isTruncated: Bool { omittedTokenCount > 0 }

    public init(
        language: String?,
        sourceRange: NSRange,
        text: String,
        tokens: [HighlightToken],
        omittedTokenCount: Int
    ) {
        self.language = language
        self.sourceRange = sourceRange
        self.text = text
        self.tokens = tokens
        self.omittedTokenCount = omittedTokenCount
    }
}

public struct HighlightedDocumentUpdate: Equatable, Sendable {
    public let restartedAtLine: Int
    public let reparsedLineCount: Int
    public let reusedSuffixLineCount: Int
    public let convergedAtLine: Int?

    public init(
        restartedAtLine: Int,
        reparsedLineCount: Int,
        reusedSuffixLineCount: Int,
        convergedAtLine: Int?
    ) {
        self.restartedAtLine = restartedAtLine
        self.reparsedLineCount = reparsedLineCount
        self.reusedSuffixLineCount = reusedSuffixLineCount
        self.convergedAtLine = convergedAtLine
    }
}

/// Incremental, actor-isolated highlighting for editable or range-materialized
/// documents.
public actor HighlightedDocument {
    private struct Line: Sendable {
        let text: String
        let tokens: [HighlightToken]
    }

    private struct Checkpoint: Sendable {
        let lineIndex: Int
        let continuation: Continuation?
    }

    private struct Build: Sendable {
        let lines: [Line]
        let checkpoints: [Checkpoint]
    }

    private let highlighter: Highlighter
    private let options: HighlightOptions
    public let checkpointInterval: Int
    public private(set) var language: String?

    private var selection: LanguageSelection
    private var source: String
    private var lines: [Line]
    private var checkpoints: [Checkpoint]

    public init(
        text: String,
        highlighter: Highlighter = .shared,
        selection requestedSelection: LanguageSelection,
        options: HighlightOptions = HighlightOptions(),
        checkpointInterval: Int = 32
    ) async throws {
        precondition(checkpointInterval > 0, "checkpointInterval must be positive")
        self.highlighter = highlighter
        self.options = options
        self.checkpointInterval = checkpointInterval
        self.language = nil
        self.selection = .plain
        self.source = ""
        self.lines = []
        self.checkpoints = []

        let resolved = try await Self.resolveSelection(
            requestedSelection,
            for: text,
            highlighter: highlighter,
            options: options
        )
        let build = try await Self.build(
            lineTexts: Self.splitLines(text),
            selection: resolved,
            highlighter: highlighter,
            options: options,
            checkpointInterval: checkpointInterval
        )
        try Task.checkCancellation()
        self.language = switch resolved {
        case .named(let name): name
        case .automatic, .plain: nil
        }
        self.selection = resolved
        self.source = text
        self.lines = build.lines
        self.checkpoints = build.checkpoints
    }

    public var text: String { source }
    public var lineCount: Int { lines.count }

    /// Applies a UTF-16 edit transactionally. Cancellation or highlighting
    /// failure leaves the previous text, tokens, and checkpoints untouched.
    @discardableResult
    public func replaceCharacters(
        in range: NSRange,
        with replacement: String
    ) async throws -> HighlightedDocumentUpdate {
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= source.utf16.count,
              let swiftRange = Self.exactRange(range, in: source)
        else { throw HighlightedDocumentError.invalidUTF16Range(range) }

        try Task.checkCancellation()
        let updatedSource = source.replacingCharacters(in: swiftRange, with: replacement)
        let newLineTexts = Self.splitLines(updatedSource)
        let changedLine = Self.lineIndex(at: range.location, in: lines)
        let restart = checkpoints.last(where: { $0.lineIndex <= changedLine })
            ?? Checkpoint(lineIndex: 0, continuation: nil)
        let restartIndex = min(restart.lineIndex, newLineTexts.count)

        var newLines = Array(lines.prefix(restartIndex))
        var newCheckpoints = checkpoints.filter { $0.lineIndex <= restartIndex }
        if newCheckpoints.last?.lineIndex != restartIndex {
            newCheckpoints.append(restart)
        }

        let suffixCount = Self.commonSuffixCount(
            old: lines.map(\.text),
            new: newLineTexts,
            after: restartIndex
        )
        let oldSuffixStart = lines.count - suffixCount
        let newSuffixStart = newLineTexts.count - suffixCount
        let lineDelta = newLineTexts.count - lines.count
        let oldCheckpointByLine = Dictionary(
            uniqueKeysWithValues: checkpoints.map { ($0.lineIndex, $0) }
        )

        var continuation = restart.continuation
        var reparsed = 0
        var convergedAt: Int?
        var index = restartIndex
        while index < newLineTexts.count {
            try Task.checkCancellation()
            let result = try await highlighter.highlight(
                newLineTexts[index],
                selection: selection,
                options: options,
                continuation: continuation
            )
            continuation = result.continuation
            newLines.append(Line(text: newLineTexts[index], tokens: result.tokens))
            reparsed += 1
            let boundary = index + 1
            if (boundary - restartIndex).isMultiple(of: checkpointInterval) {
                newCheckpoints.append(Checkpoint(
                    lineIndex: boundary,
                    continuation: continuation
                ))
            }

            let oldBoundary = boundary - lineDelta
            if boundary >= newSuffixStart,
               oldBoundary >= oldSuffixStart,
               let oldCheckpoint = oldCheckpointByLine[oldBoundary],
               continuation == oldCheckpoint.continuation {
                convergedAt = boundary
                if oldBoundary < lines.count {
                    newLines.append(contentsOf: lines[oldBoundary...])
                }
                for checkpoint in checkpoints where checkpoint.lineIndex > oldBoundary {
                    newCheckpoints.append(Checkpoint(
                        lineIndex: checkpoint.lineIndex + lineDelta,
                        continuation: checkpoint.continuation
                    ))
                }
                break
            }
            index += 1
        }

        try Task.checkCancellation()
        let reused = convergedAt.map { newLineTexts.count - $0 } ?? 0
        source = updatedSource
        lines = newLines
        checkpoints = Self.normalizedCheckpoints(
            newCheckpoints,
            lineCount: newLines.count
        )
        return HighlightedDocumentUpdate(
            restartedAtLine: restartIndex,
            reparsedLineCount: reparsed,
            reusedSuffixLineCount: reused,
            convergedAtLine: convergedAt
        )
    }

    /// Returns a self-contained range snapshot. Intersecting tokens are
    /// clipped and rebased to the returned `text`.
    public func snapshot(
        in requestedRange: NSRange? = nil,
        maximumTokens: Int? = nil
    ) throws -> HighlightedDocumentSnapshot {
        if let maximumTokens {
            precondition(maximumTokens >= 0, "maximumTokens must not be negative")
        }
        let range = requestedRange ?? NSRange(location: 0, length: source.utf16.count)
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= source.utf16.count,
              let swiftRange = Self.exactRange(range, in: source)
        else { throw HighlightedDocumentError.invalidUTF16Range(range) }

        var candidates: [HighlightToken] = []
        var lineOffset = 0
        for line in lines {
            for token in line.tokens {
                let global = NSRange(
                    location: lineOffset + token.range.location,
                    length: token.range.length
                )
                let intersection = NSIntersectionRange(global, range)
                guard intersection.length > 0 else { continue }
                candidates.append(HighlightToken(
                    range: NSRange(
                        location: intersection.location - range.location,
                        length: intersection.length
                    ),
                    scopes: token.scopes
                ))
            }
            lineOffset += line.text.utf16.count
        }
        let count = min(maximumTokens ?? candidates.count, candidates.count)
        return HighlightedDocumentSnapshot(
            language: language,
            sourceRange: range,
            text: String(source[swiftRange]),
            tokens: Array(candidates.prefix(count)),
            omittedTokenCount: candidates.count - count
        )
    }

    private static func resolveSelection(
        _ requested: LanguageSelection,
        for text: String,
        highlighter: Highlighter,
        options: HighlightOptions
    ) async throws -> LanguageSelection {
        switch requested {
        case .plain:
            return .plain
        case .named(let name):
            guard let canonical = highlighter.language(named: name)?.name else {
                throw HighlightError.unknownLanguage(name)
            }
            return .named(canonical)
        case .automatic:
            let detected = try await highlighter.highlight(
                text,
                selection: .automatic,
                options: options
            )
            return detected.language.map(LanguageSelection.named) ?? .plain
        }
    }

    private static func build(
        lineTexts: [String],
        selection: LanguageSelection,
        highlighter: Highlighter,
        options: HighlightOptions,
        checkpointInterval: Int
    ) async throws -> Build {
        var lines: [Line] = []
        lines.reserveCapacity(lineTexts.count)
        var checkpoints = [Checkpoint(lineIndex: 0, continuation: nil)]
        var continuation: Continuation?
        for (index, lineText) in lineTexts.enumerated() {
            try Task.checkCancellation()
            let result = try await highlighter.highlight(
                lineText,
                selection: selection,
                options: options,
                continuation: continuation
            )
            continuation = result.continuation
            lines.append(Line(text: lineText, tokens: result.tokens))
            let boundary = index + 1
            if boundary.isMultiple(of: checkpointInterval) {
                checkpoints.append(Checkpoint(
                    lineIndex: boundary,
                    continuation: continuation
                ))
            }
        }
        try Task.checkCancellation()
        return Build(lines: lines, checkpoints: checkpoints)
    }

    private static func splitLines(_ text: String) -> [String] {
        let source = text as NSString
        guard source.length > 0 else { return [""] }
        var lines: [String] = []
        var start = 0
        var cursor = 0
        var endedWithTerminator = false
        while cursor < source.length {
            let unit = source.character(at: cursor)
            guard unit == 0x0A || unit == 0x0D else {
                cursor += 1
                endedWithTerminator = false
                continue
            }
            cursor += 1
            if unit == 0x0D,
               cursor < source.length,
               source.character(at: cursor) == 0x0A {
                cursor += 1
            }
            lines.append(source.substring(with: NSRange(
                location: start,
                length: cursor - start
            )))
            start = cursor
            endedWithTerminator = true
        }
        if start < source.length {
            lines.append(source.substring(from: start))
        } else if endedWithTerminator {
            lines.append("")
        }
        return lines
    }

    private static func exactRange(
        _ range: NSRange,
        in text: String
    ) -> Range<String.Index>? {
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= text.utf16.count
        else { return nil }
        let utf16 = text.utf16
        let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: range.location)
        let upperUTF16 = utf16.index(lowerUTF16, offsetBy: range.length)
        guard let lower = String.Index(lowerUTF16, within: text),
              let upper = String.Index(upperUTF16, within: text)
        else { return nil }
        return lower..<upper
    }

    private static func lineIndex(at location: Int, in lines: [Line]) -> Int {
        var offset = 0
        for (index, line) in lines.enumerated() {
            let end = offset + line.text.utf16.count
            if location < end || index == lines.count - 1 { return index }
            offset = end
        }
        return 0
    }

    private static func commonSuffixCount(
        old: [String],
        new: [String],
        after restart: Int
    ) -> Int {
        let maximum = min(old.count, new.count) - restart
        guard maximum > 0 else { return 0 }
        var count = 0
        while count < maximum,
              old[old.count - count - 1] == new[new.count - count - 1] {
            count += 1
        }
        return count
    }

    private static func normalizedCheckpoints(
        _ checkpoints: [Checkpoint],
        lineCount: Int
    ) -> [Checkpoint] {
        var seen: Set<Int> = []
        return checkpoints
            .filter { $0.lineIndex >= 0 && $0.lineIndex <= lineCount }
            .sorted { $0.lineIndex < $1.lineIndex }
            .filter { seen.insert($0.lineIndex).inserted }
    }
}
