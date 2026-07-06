import SwiftUI

struct SidebarView: View {
    @Binding var selectedPage: AppPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GMK67")
                    .font(.headline)
                Text("Keyboard Driver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(AppPage.userPages) { page in
                    SidebarButton(page: page, selectedPage: $selectedPage)
                }
            }

            Divider()
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Developer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
                SidebarButton(page: .developer, selectedPage: $selectedPage)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SidebarButton: View {
    let page: AppPage
    @Binding var selectedPage: AppPage?

    private var isSelected: Bool {
        selectedPage == page
    }

    var body: some View {
        Button {
            selectedPage = page
        } label: {
            Label(page.title, systemImage: page.systemImage)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 8)
    }
}
