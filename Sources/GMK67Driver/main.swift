import Foundation

do {
    try run(CommandLine.arguments)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
