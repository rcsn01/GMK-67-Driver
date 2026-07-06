import Foundation
import GMK67Core

do {
    try runGMK67Command(CommandLine.arguments)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
