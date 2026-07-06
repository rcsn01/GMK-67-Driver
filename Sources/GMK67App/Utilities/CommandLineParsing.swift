import Foundation

func splitCommandLine(_ text: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quote: Character?
    var isEscaping = false

    for character in text {
        if isEscaping {
            current.append(character)
            isEscaping = false
            continue
        }

        if character == "\\" {
            isEscaping = true
            continue
        }

        if character == "\"" || character == "'" {
            if quote == character {
                quote = nil
            } else if quote == nil {
                quote = character
            } else {
                current.append(character)
            }
            continue
        }

        if character.isWhitespace && quote == nil {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
            continue
        }

        current.append(character)
    }

    if !current.isEmpty {
        result.append(current)
    }
    return result
}

func quoteCommandToken(_ token: String) -> String {
    guard token.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" }) else {
        return token
    }
    var quoted = "\""
    for character in token {
        if character == "\"" || character == "\\" {
            quoted.append("\\")
        }
        quoted.append(character)
    }
    quoted.append("\"")
    return quoted
}
