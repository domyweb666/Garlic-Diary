import SwiftUI

@main
struct SuanshuApp: App {
    @State private var store = AppStore()
    @State private var ui = UIState()
    @State private var toaster = Toaster()
    @State private var speech = SpeechService()
    @State private var pile = PileModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(ui)
                .environment(toaster)
                .environment(speech)
                .environment(pile)
                .tint(T.accent)
        }
    }
}
