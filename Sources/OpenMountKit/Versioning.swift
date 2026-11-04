import Foundation

public enum Versioning {
    /// Compares dotted versions numerically ("0.10.0" > "0.9.3"); a leading "v" is ignored.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            let t = s.hasPrefix("v") ? String(s.dropFirst()) : s
            return t.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
