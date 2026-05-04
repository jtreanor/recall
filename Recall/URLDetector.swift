import Foundation

func detectFirstURL(in text: String) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    return detector.firstMatch(in: text, options: [], range: range)?.url
}
