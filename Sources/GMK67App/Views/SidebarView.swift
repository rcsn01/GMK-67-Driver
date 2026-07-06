import SwiftUI

struct SidebarView: View {
    @Binding var selectedPage: AppPage?

    var body: some View {
        List(selection: $selectedPage) {
            Section {
                ForEach(AppPage.userPages) { page in
                    NavigationLink(value: page) {
                        Label(page.title, systemImage: page.systemImage)
                    }
                }
            }

            Section("Developer") {
                NavigationLink(value: AppPage.developer) {
                    Label(AppPage.developer.title, systemImage: AppPage.developer.systemImage)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
