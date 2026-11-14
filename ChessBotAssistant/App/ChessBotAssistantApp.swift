import SwiftUI

@main
struct ChessBotAssistantApp: App {
    @StateObject private var viewModel = AssistantViewModel()

    var body: some Scene {
        WindowGroup {
            MainAssistantView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.handleIncomingURL(url)
                }
        }
    }
}
