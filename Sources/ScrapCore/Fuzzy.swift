import Foundation

public enum Fuzzy {
    /// Subsequence match score, or nil if `query` doesn't match. Higher is better.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        if q.isEmpty { return 0 }
        var qi = 0, score = 0, prev = -2
        for (i, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            score += 1
            if i == prev + 1 { score += 5 }
            if i == 0 || !c[i - 1].isLetter && !c[i - 1].isNumber { score += 3 }
            prev = i
            qi += 1
        }
        return qi == q.count ? score - c.count / 8 : nil
    }

    public static func rank<T>(_ query: String, _ items: [T], by key: (T) -> String) -> [T] {
        items.enumerated()
            .compactMap { i, item in score(query, in: key(item)).map { (i, $0, item) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .map(\.2)
    }
}
