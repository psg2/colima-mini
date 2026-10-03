import Foundation

// Docker prints RFC 3339 times with nanoseconds or a UTC offset, and uses the
// zero time for "never".
package enum DockerDate {
    package static func parse(_ text: String?) -> Date? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
            !text.hasPrefix("0001-01-01")
        else { return nil }
        // ISO8601DateFormatter reads at most milliseconds.
        if let fraction = text.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = text[fraction].dropFirst().prefix(3)
            text.replaceSubrange(
                fraction, with: "." + digits.padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
