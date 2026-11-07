import SwiftUI

/// 三頁橫滑（左＝籃子、中＝剝今天、右＝設定），上面三個點。
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(PileModel.self) private var pile
    @Environment(SpeechService.self) private var speech
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tilt = TiltSensor()

    var body: some View {
        @Bindable var ui = ui
        ZStack(alignment: .top) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    BasketPage()
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    MainPage()
                        .containerRelativeFrame(.horizontal)
                        .id(1)
                    SettingsPage()
                        .containerRelativeFrame(.horizontal)
                        .id(2)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $ui.page)
            .scrollIndicators(.hidden)
            .scrollDisabled(ui.locked)
            .fullScreenCover(isPresented: reviewPresented) { ReviewSheet() }

            PageDots(current: ui.page ?? 1, hidden: ui.locked) { i in
                withAnimation(.easeInOut(duration: 0.3)) { ui.page = i }
            }
            .padding(.top, 10)
        }
        .background(T.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) { ToastView() }
        .fullScreenCover(isPresented: onboardingPresented) { OnboardingView() }
        .onAppear(perform: setup)
        .onChange(of: scenePhase) { _, phase in handle(phase) }
    }

    private var reviewPresented: Binding<Bool> {
        Binding(get: { ui.review != nil }, set: { if !$0 { ui.review = nil } })
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(get: { !store.s.onboarded }, set: { shown in
            if !shown {
                store.s.onboarded = true
                store.save()
            }
        })
    }

    private func setup() {
        pile.reduceMotion = reduceMotion
        store.syncFeedbackFlags()
        tilt.onGravity = { x, y in pile.setGravity(x, y) }
        tilt.start()
        _ = store.dayChanged()
        Reminders.reschedule(store.s)
        Feedback.shared.warmUp()
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if store.dayChanged() {
                ui.peel = nil
                pile.dim = false
                ui.viewMonth = nil
                pile.requestRebuild()
            }
            tilt.start()
            pile.start()
            Reminders.reschedule(store.s)
        case .inactive, .background:
            tilt.stop()
            speech.finish()
        @unknown default:
            break
        }
    }
}

struct PageDots: View {
    let current: Int
    let hidden: Bool
    let onTap: (Int) -> Void

    private let labels = ["籃子", "剝今天", "設定"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Button {
                    onTap(i)
                } label: {
                    Circle()
                        .fill(i == current ? T.fg : T.fg3)
                        .frame(width: 8, height: 8)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(labels[i]))
                .accessibilityAddTraits(i == current ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .animation(.easeInOut(duration: 0.25), value: hidden)
    }
}
