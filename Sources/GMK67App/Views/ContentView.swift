import SwiftUI

struct ContentView: View {
    @StateObject private var model = DriverModel()
    @State private var selectedPage: AppPage? = .rgb

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedPage: $selectedPage)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                DeviceStatusBanner(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                GeometryReader { geometry in
                    let keyboardHeight = geometry.size.height * 0.5

                    VStack(spacing: 0) {
                        VisualKeyboardView(model: model)
                            .padding(.horizontal, 18)
                            .frame(height: keyboardHeight)

                        Divider()
                            .padding(.horizontal, 18)

                        ScrollView {
                            pageSettings(for: selectedPage ?? .rgb)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: geometry.size.height - keyboardHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ConsoleView(text: model.output, isRunning: model.isRunning) {
                    model.clearOutput()
                }
            }
            .navigationTitle("GMK67")
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
