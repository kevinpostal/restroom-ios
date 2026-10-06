import Foundation

/// How to get through a locked restroom door. From a PottyPins pin or Refuge free text.
enum Access: Equatable {
    case code(String)   // digits to punch, e.g. "125"
    case onReceipt      // code printed on the receipt
    case askStaff       // ask at the counter
    case open           // explicitly no code needed

    /// Compact row text.
    var title: String {
        switch self {
        case .code(let c): "Code \(c)"
        case .onReceipt: "Code on receipt"
        case .askStaff: "Ask staff for code"
        case .open: "No code needed"
        }
    }

    /// VoiceOver: keypad digits spoken one by one ("Door code 1 2 5").
    var spoken: String {
        guard case .code(let c) = self else { return title }
        let keypadOnly = c.allSatisfy { $0.isNumber || $0 == "*" || $0 == "#" }
        return "Door code " + (keypadOnly ? c.map(String.init).joined(separator: " ") : c)
    }

    /// Heuristic over Refuge `directions` + `comment`. Order matters: negation → digits → receipt → ask/bare mention.
    static func parse(_ text: String) -> Access? {
        let t = text.lowercased()
        guard t.range(of: #"\b(code|combo|combination|keypad|key pad|pin)\b"#, options: .regularExpression) != nil else { return nil }
        if t.range(of: #"\b(no|don.?t|doesn.?t|not|without)\b[^.]{0,20}\b(code|pin|combo)\b"#, options: .regularExpression) != nil { return nil }
        if let m = t.range(of: #"\b(code|combo|combination|pin)\b[^0-9\n]{0,12}([0-9][0-9*#]{2,7})"#, options: .regularExpression) {
            let digits = String(t[m]).replacingOccurrences(of: #"^.*?([0-9][0-9*#]{2,7})$"#, with: "$1", options: .regularExpression)
            return .code(digits)
        }
        if t.contains("receipt") { return .onReceipt }
        return .askStaff
    }

    /// PottyPins `pin` strings: digits (optionally with a trailing note like "(+ ENTER)"), or "No PIN required".
    static func fromPin(_ pin: String) -> Access? {
        let p = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        if p.range(of: #"(?i)\b(no pin|none|not required|no code)\b"#, options: .regularExpression) != nil { return .open }
        return .code(p)
    }
}
