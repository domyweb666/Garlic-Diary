import SwiftUI

/// 第一次打開：三步，照網頁版
struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var step = 0
    @State private var anchor = "刷完牙"
    @State private var restart = ""

    private let anchors = ["刷完牙", "關燈前", "躺上床前"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            switch step {
            case 0:
                step0
            case 1:
                step1
            default:
                step2
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
        .onAppear {
            anchor = store.s.settings.anchor
            restart = store.s.settings.restart
        }
    }

    private var step0: some View {
        VStack(spacing: 12) {
            GarlicGlyph(rates: [.good, .mid, .bad], seeds: [2, 1, 1], sprout: true, label: "蒜數")
                .frame(width: 120, height: 120)
                .padding(.bottom, 12)
            Text("蒜數")
                .font(.largeTitle.bold())
            Text("白天想到就說一句，那一瓣就長出一條根。")
                .font(.body)
                .foregroundStyle(T.fg2)
                .multilineTextAlignment(.center)
            Text("睡前把今天剝成三瓣：上午、下午、晚上，\n每瓣點一下順、普通、卡。")
                .font(.body)
                .foregroundStyle(T.fg2)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "好") { step = 1 }
                .padding(.top, 18)
            Text("1 / 3")
                .font(.footnote)
                .foregroundStyle(T.fg2)
                .padding(.top, 6)
        }
    }

    private var step1: some View {
        VStack(spacing: 12) {
            Text("在什麼之後剝？")
                .font(.title.bold())
            Text("選一個每天晚上都會做的事。\n做完它，就剝今天。")
                .font(.body)
                .foregroundStyle(T.fg2)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(anchors, id: \.self) { a in
                    Chip(title: a, pressed: anchor == a) { anchor = a }
                }
            }
            .padding(.top, 6)
            PrimaryButton(title: "下一步") { step = 2 }
                .padding(.top, 18)
            Text("2 / 3")
                .font(.footnote)
                .foregroundStyle(T.fg2)
                .padding(.top, 6)
        }
    }

    private var step2: some View {
        VStack(spacing: 12) {
            Text("先寫好斷掉那天怎麼辦")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("一定會有沒剝的日子。到時候照這句做就好。")
                .font(.body)
                .foregroundStyle(T.fg2)
                .multilineTextAlignment(.center)
            TextField("斷了不補，今晚剝一顆就算回來。", text: $restart, axis: .vertical)
                .lineLimit(2...4)
                .font(.title3)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("大部分人要一到幾個月才覺得不費力，前幾週覺得累是正常的。")
                .font(.subheadline)
                .foregroundStyle(T.fg2)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "記住了，開始") { finish() }
                .padding(.top, 18)
            Text("3 / 3")
                .font(.footnote)
                .foregroundStyle(T.fg2)
                .padding(.top, 6)
        }
    }

    private func finish() {
        store.s.settings.anchor = anchor
        let r = restart.trimmed
        if !r.isEmpty { store.s.settings.restart = r }
        store.s.onboarded = true
        store.save()
    }
}
