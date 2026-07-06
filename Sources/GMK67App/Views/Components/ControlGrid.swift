import SwiftUI

struct ControlGrid<Content: View>: View {
    private let minimumWidth: CGFloat
    private let content: Content

    init(minimumWidth: CGFloat = 140, @ViewBuilder content: () -> Content) {
        self.minimumWidth = minimumWidth
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            content
        }
    }
}
