import SwiftUI

struct ContentView: View {
    @StateObject private var model = DriverModel()
    @State private var selectedPage: AppPage? = .rgb

    var body: some View {
        NavigationSplitView {
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
            .navigationTitle("GMK67")
        } detail: {
            VStack(spacing: 0) {
                DeviceStatusBanner(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    VisualKeyboardView(model: model)
                        .padding(.horizontal, 18)
                        .frame(maxHeight: .infinity)

                    Divider()
                        .padding(.horizontal, 18)

                    ScrollView {
                        pageSettings(for: selectedPage ?? .rgb)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)

                ConsoleView(text: model.output, isRunning: model.isRunning) {
                    model.clearOutput()
                }
            }
        }
        .task {
            model.refreshDeviceStatusIfNeeded()
        }
    }

    @ViewBuilder
    private func pageSettings(for page: AppPage) -> some View {
        switch page {
        case .rgb:
            VStack(alignment: .leading, spacing: 18) {
                QuickPresetsPanel(model: model)
                SelectedKeyColorControls(model: model)
                RGBPanel(model: model)
            }
        case .profiles:
            ProfilePanel(model: model)
        case .keymap:
            VStack(alignment: .leading, spacing: 18) {
                SelectedKeyRemapControls(model: model)
                KeymapPanel(model: model)
            }
        case .macros:
            MacroPanel(model: model)
        case .device:
            DevicePanel(model: model)
        case .developer:
            VStack(alignment: .leading, spacing: 18) {
                DeveloperToolsPanel(model: model)
                LightingPanel(model: model)
                AdvancedPanel(model: model)
            }
        }
    }
}
