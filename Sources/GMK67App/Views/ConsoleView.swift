import SwiftUI

struct ConsoleView: View {
    let text: String
    let isRunning: Bool
    let clear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Output")
                    .font(.headline)
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 18, height: 18)
                }
                Spacer()
                Button("Clear", action: clear)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ScrollView {
                Text(text.isEmpty ? "No output yet." : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
