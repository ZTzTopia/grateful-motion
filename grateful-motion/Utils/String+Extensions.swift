import Foundation

extension String {
    func customPercentEncoded() -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+")
        allowed.remove(charactersIn: "&")
        return self.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    func normalize() -> String {
        self.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "’", with: "'")
    }
}
