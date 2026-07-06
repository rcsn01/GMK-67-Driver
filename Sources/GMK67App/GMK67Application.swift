import SwiftUI
import Foundation
import GMK67Core

@main
struct GMK67Application: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if let commandIndex = CommandLine.arguments.firstIndex(of: "--gmk67") {
            do {
                let passthrough = Array(CommandLine.arguments.dropFirst(commandIndex + 1))
                guard !passthrough.isEmpty else {
                    fputs("error: --gmk67 requires a driver command.\n", stderr)
                    exit(1)
                }
                let args = ["gmk67"] + passthrough
                print("$ \(args.joined(separator: " "))")
                try runGMK67Command(args)
                exit(0)
            } catch {
                fputs("error: \(error)\n", stderr)
                exit(1)
            }
        }

        if CommandLine.arguments.contains("--rgb-space-green-test") {
            do {
                var setArgs = ["gmk67", "rgb-set-key", "space", "00FF00"]
                if CommandLine.arguments.contains("--legacy-table") {
                    setArgs.append("--legacy-table")
                }
                print("$ \(setArgs.joined(separator: " "))")
                try runGMK67Command(setArgs)
                fflush(nil)
                Thread.sleep(forTimeInterval: 2.0)
                print("\n$ gmk67 rgb-dump 0 0 9 --json")
                try runGMK67Command(["gmk67", "rgb-dump", "0", "0", "9", "--json"])
                exit(0)
            } catch {
                fputs("error: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
