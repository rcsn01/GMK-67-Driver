import SwiftUI

struct ContentView: View {
    @StateObject private var model = DriverModel()
    @State private var selectedPage: AppPage? = .rgb
    @State private var showsKeyboardPreview = true

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedPage: $selectedPage)
                .frame(width: 220)

            Divider()

            VStack(spacing: 0) {
                DeviceStatusBanner(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                HStack(spacing: 12) {
                    Text((selectedPage ?? .rgb).title)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    CommandButton(
                        showsKeyboardPreview ? "Hide Keyboard" : "Show Keyboard",
                        systemImage: showsKeyboardPreview ? "keyboard.chevron.compact.down" : "keyboard"
                    ) {
                        showsKeyboardPreview.toggle()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                GeometryReader { geometry in
                    let keyboardHeight = min(max(geometry.size.height * 0.38, 190), 310)

                    VStack(spacing: 0) {
                        if showsKeyboardPreview {
                            VisualKeyboardView(model: model)
                                .padding(.horizontal, 18)
                                .frame(height: keyboardHeight)

                            Divider()
                                .padding(.horizontal, 18)
                        }

                        ScrollView {
                            pageSettings(for: selectedPage ?? .rgb)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: showsKeyboardPreview ? geometry.size.height - keyboardHeight : geometry.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ConsoleView(text: model.output, isRunning: model.isRunning) {
                    model.clearOutput()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 700)
        .task {
            model.refreshDeviceStatusIfNeeded()
        }
        .onDisappear {
            model.stopLiveMonitoring()
        }
    }

    @ViewBuilder
    private func pageSettings(for page: AppPage) -> some View {
        switch page {
        case .rgb:
            RGBPanel(model: model)
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
