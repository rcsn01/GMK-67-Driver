import SwiftUI

struct ConsoleView: View {
    let text: String
    let isRunning: Bool
    let clear: () -> Void

    @State private var isExpanded = false

    private var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastLine = trimmed.split(separator: "\n", omittingEmptySubsequences: false).last else {
            return ""
        }
        return String(lastLine).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse output" : "Expand output")

                Text("Output")
                    .font(.headline)

                if isRunning {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 18, height: 18)
                }

                if !isExpanded {
                    if preview.isEmpty {
                        Text("Hidden")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                Button("Clear", action: clear)
                    .disabled(text.isEmpty && !isRunning)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
            }

            if isExpanded {
                Divider()

                ScrollView {
                    Text(text.isEmpty ? "No output yet." : text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(minHeight: 160, maxHeight: 280)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
