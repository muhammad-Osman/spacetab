import Foundation

/// Fuzzy matching of window titles and app names, so `vsc` finds
/// *Visual Studio Code*.
enum WindowSearch {
    /// The windows that match, best match first. Equal matches keep their
    /// order (most recently used first). An empty query matches everything.
    static func filter(_ windows: [WindowInfo], query: String) -> [WindowInfo] {
        let query = fold(query.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return windows }
        return windows.enumerated()
            .compactMap { offset, window in
                score(fold("\(window.title) \(window.appName)"), query: query).map { (window, $0, offset) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    /// How well `query` matches `text`, both already folded. Nil when the
    /// query's characters don't all appear in order.
    ///
    /// A contiguous match beats a scattered one, a match at the start of the
    /// text or of a word beats one in the middle, and consecutive characters
    /// beat gaps.
    static func score(_ text: String, query: String) -> Int? {
        let text = Array(text)
        let query = Array(query)
        guard !query.isEmpty else { return 0 }

        var score = 0
        var textIndex = 0
        var previousMatch: Int?
        for character in query {
            guard let found = text[textIndex...].firstIndex(of: character) else { return nil }
            score += 1
            if found == 0 || isWordBoundary(text[found - 1]) {
                score += 8
            }
            if let previousMatch {
                score += found == previousMatch + 1 ? 5 : -min(found - previousMatch - 1, 5)
            }
            previousMatch = found
            textIndex = found + 1
        }

        let joined = String(text)
        let wanted = String(query)
        if joined.hasPrefix(wanted) {
            score += 40
        } else if joined.contains(wanted) {
            score += 20
        }
        return score
    }

    /// Lowercased, without accents, so "resume" finds "Résumé".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private static func isWordBoundary(_ character: Character) -> Bool {
        character.isWhitespace || "-_./\\:—–·|()[]".contains(character)
    }
}
