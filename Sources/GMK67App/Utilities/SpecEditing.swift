import Foundation

func upsertSpec(_ specs: String, key: String, value: String) -> String {
    let normalizedKey = specKeyToken(key)
    let replacement = "\(key)=\(value)"
    var didReplace = false
    var tokens = splitCommandLine(specs).compactMap { token -> String? in
        guard let equalsIndex = token.firstIndex(of: "=") else { return token }
        let existingKey = String(token[..<equalsIndex])
        if specKeyToken(existingKey) == normalizedKey {
            if didReplace {
                return nil
            }
            didReplace = true
            return replacement
        }
        return token
    }

    if !didReplace {
        tokens.append(replacement)
    }
    return tokens.joined(separator: " ")
}

func removeSpec(_ specs: String, key: String) -> String {
    let normalizedKey = specKeyToken(key)
    return splitCommandLine(specs).filter { token in
        guard let equalsIndex = token.firstIndex(of: "=") else { return true }
        let existingKey = String(token[..<equalsIndex])
        return specKeyToken(existingKey) != normalizedKey
    }.joined(separator: " ")
}

func valueForSpecKey(_ key: String, in specs: String) -> String? {
    let normalizedKey = specKeyToken(key)
    for token in splitCommandLine(specs) {
        guard let equalsIndex = token.firstIndex(of: "=") else { continue }
        let existingKey = String(token[..<equalsIndex])
        guard specKeyToken(existingKey) == normalizedKey else { continue }
        return String(token[token.index(after: equalsIndex)...])
    }
    return nil
}

func specKeyToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
}
