import Foundation

/// One matching line.
public struct SearchHit: Equatable, Identifiable {
    public let pad: Int
    /// 1-based line number in the pad.
    public let line: Int
    /// The line as shown: trimmed, and cropped around the match if it is long.
    public let text: String
    /// Where in `text` to emphasise.
    public let matches: [NSRange]
    /// Where to select in the pad's own text (UTF-16 offsets): the first match.
    public let target: NSRange
    public let score: Double
    public var id: String { "\(pad):\(line)" }
}

public struct SearchResult: Equatable {
    public var hits: [SearchHit]
    /// True when nothing matched exactly, so these are the nearest things (typos, or only some of the words).
    public var isClosest: Bool
    public static let empty = SearchResult(hits: [], isClosest: false)
}

/// Searches the text of all the pads. Words match without regard to case or accents, as whole words or parts of words;
/// a word with a small typo still finds its target ("recipie" finds "recipe"); and when nothing matches exactly the
/// nearest lines are offered instead.
public enum PadSearch {
    public static let maxWords = 6
    private static let compare: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let displayLength = 90
    private static let wordPattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}_]+")

    private struct Candidate {
        var pad: Int
        var line: Int
        var lineRange: NSRange
        var text: String
        var matchedWords: Int
        var exactWords: Int
        var ranges: [NSRange]   // in `text`
        var score: Double
    }

    public static func search(_ query: String, in pads: [(number: Int, text: String)], limit: Int = 30, perPad: Int = 3) -> SearchResult {
        let words = query.split(whereSeparator: \.isWhitespace).prefix(maxWords).map(String.init)
        guard !words.isEmpty else { return .empty }
        let folded: [String] = words.map(fold)
        let phrase = words.joined(separator: " ")

        var all: [Candidate] = []
        for pad in pads {
            let ns = pad.text as NSString
            var lineNumber = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
                lineNumber += 1
                if range.length == 0 { return }
                if let candidate = match(line: ns.substring(with: range), lineRange: range, number: lineNumber, pad: pad.number,
                                         words: words, folded: folded, phrase: phrase) {
                    all.append(candidate)
                }
            }
        }
        if all.isEmpty { return .empty }

        // Prefer lines holding every word; exact ones over typo-tolerant ones; and only then the partial ones.
        let full = all.filter { $0.matchedWords == words.count }
        let exactFull = full.filter { $0.exactWords == words.count }
        let chosen: [Candidate]
        let closest: Bool
        if !exactFull.isEmpty {
            chosen = exactFull
            closest = false
        } else if !full.isEmpty {
            chosen = full
            closest = true
        } else {
            chosen = all
            closest = true
        }

        let ranked = chosen.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.pad != b.pad { return a.pad < b.pad }
            return a.line < b.line
        }
        var perPadCount: [Int: Int] = [:]
        var hits: [SearchHit] = []
        for candidate in ranked {
            let count = perPadCount[candidate.pad, default: 0]
            if count >= perPad { continue }
            perPadCount[candidate.pad] = count + 1
            hits.append(makeHit(candidate))
            if hits.count >= limit { break }
        }
        return SearchResult(hits: hits, isClosest: closest)
    }

    // MARK: Matching one line

    private static func match(line: String, lineRange: NSRange, number: Int, pad: Int, words: [String], folded: [String], phrase: String) -> Candidate? {
        let ns = line as NSString
        var lineWords: [(range: NSRange, folded: String)]?   // computed only if a typo-tolerant match is needed
        var ranges: [NSRange] = []
        var score = 0.0
        var matched = 0
        var exact = 0

        for (index, word) in words.enumerated() {
            if let hit = exactMatch(word, in: ns) {
                ranges.append(hit.range)
                score += hit.score
                matched += 1
                exact += 1
            } else if folded[index].count >= 4 {
                if lineWords == nil { lineWords = wordsOf(ns) }
                if let hit = typoMatch(folded[index], in: lineWords ?? []) {
                    ranges.append(hit.range)
                    score += hit.score
                    matched += 1
                }
            }
        }
        if matched == 0 { return nil }
        if matched == words.count { score += 3 }
        if words.count > 1, ns.range(of: phrase, options: compare).location != NSNotFound { score += 4 }
        if number == 1 { score += 1 }
        score *= 1 + 0.5 / (1 + Double(ns.length) / 60)
        return Candidate(pad: pad, line: number, lineRange: lineRange, text: line, matchedWords: matched, exactWords: exact, ranges: ranges, score: score)
    }

    private static func exactMatch(_ word: String, in line: NSString) -> (range: NSRange, score: Double)? {
        var best: (range: NSRange, score: Double)?
        var from = 0
        while from < line.length {
            let found = line.range(of: word, options: compare, range: NSRange(location: from, length: line.length - from))
            if found.location == NSNotFound || found.length == 0 { break }
            let atStart = found.location == 0 || !isWordCharacter(line.character(at: found.location - 1))
            let atEnd = found.upperBound >= line.length || !isWordCharacter(line.character(at: found.upperBound))
            let score: Double = atStart && atEnd ? 5 : (atStart ? 4 : 3)
            if best == nil || score > best!.score { best = (found, score) }
            if score == 5 { break }
            from = found.upperBound
        }
        return best
    }

    /// The word nearest to `word` within a small edit distance (counting a swap of two letters as one edit).
    private static func typoMatch(_ word: String, in lineWords: [(range: NSRange, folded: String)]) -> (range: NSRange, score: Double)? {
        let allowed = word.count >= 8 ? 2 : 1
        var best: (range: NSRange, score: Double, distance: Int)?
        for candidate in lineWords {
            let length = candidate.folded.count
            if length + allowed < word.count || length > 40 { continue }
            var distance = editDistance(candidate.folded, word)
            // Someone still typing the word: compare with the start of the line's word of the same length.
            if length > word.count {
                let startDistance = editDistance(String(candidate.folded.prefix(word.count)), word)
                distance = min(distance, startDistance)
            }
            if distance <= allowed, best == nil || distance < best!.distance {
                best = (candidate.range, distance == 0 ? 2.5 : 2, distance)
            }
        }
        return best.map { (range: $0.range, score: $0.score) }
    }

    private static func wordsOf(_ line: NSString) -> [(range: NSRange, folded: String)] {
        var result: [(range: NSRange, folded: String)] = []
        for m in wordPattern.matches(in: line as String, range: NSRange(location: 0, length: line.length)) {
            result.append((m.range, fold(line.substring(with: m.range))))
        }
        return result
    }

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || unit == 95
    }

    /// Optimal string alignment distance: insertions, deletions, substitutions and swaps of neighbours each cost one.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a.unicodeScalars), t = Array(b.unicodeScalars)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: t.count + 1), count: s.count + 1)
        for i in 0...s.count { d[i][0] = i }
        for j in 0...t.count { d[0][j] = j }
        for i in 1...s.count {
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var value = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] { value = min(value, d[i - 2][j - 2] + 1) }
                d[i][j] = value
            }
        }
        return d[s.count][t.count]
    }

    // MARK: Display

    private static func makeHit(_ c: Candidate) -> SearchHit {
        let full = c.text as NSString
        let sortedRanges = merged(c.ranges)
        let first = sortedRanges.first ?? NSRange(location: 0, length: 0)
        let target = NSRange(location: c.lineRange.location + first.location, length: first.length)

        // Trim the line, then crop it around the first match when it is long.
        var lead = 0
        while lead < full.length, isSpace(full.character(at: lead)) { lead += 1 }
        var end = full.length
        while end > lead, isSpace(full.character(at: end - 1)) { end -= 1 }
        var window = NSRange(location: lead, length: end - lead)
        var prefix = "", suffix = ""
        if window.length > displayLength {
            let start = max(window.location, first.location - 30)
            let length = min(displayLength, window.upperBound - start)
            window = full.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: length))
            window = NSIntersectionRange(window, NSRange(location: lead, length: end - lead))
            if window.location > lead { prefix = "…" }
            if window.upperBound < end { suffix = "…" }
        }
        let shown = prefix + full.substring(with: window) + suffix
        let shift = (prefix as NSString).length - window.location
        var shownRanges: [NSRange] = []
        for r in sortedRanges {
            let clipped = NSIntersectionRange(r, window)
            if clipped.length > 0 { shownRanges.append(NSRange(location: clipped.location + shift, length: clipped.length)) }
        }
        return SearchHit(pad: c.pad, line: c.line, text: shown, matches: shownRanges, target: target, score: c.score)
    }

    private static func isSpace(_ unit: unichar) -> Bool { unit == 32 || unit == 9 || unit == 160 }

    private static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for r in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = result.last, r.location <= last.upperBound {
                result[result.count - 1] = NSUnionRange(last, r)
            } else {
                result.append(r)
            }
        }
        return result
    }
}
