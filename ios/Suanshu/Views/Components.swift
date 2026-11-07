import SwiftUI

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension View {
    /// 白色圓角卡（網頁版的 .card／.list）
    func card() -> some View {
        self
            .background(T.card, in: RoundedRectangle(cornerRadius: T.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: T.cardRadius, style: .continuous))
    }

    /// 清單列：左右 18、上下 10、最少 56 高
    func rowFrame(minHeight: CGFloat = 56) -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
    }

    /// 單行輸入欄
    func field() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(T.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 按鈕

struct PrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(isEnabled ? T.onAccent : T.fg3)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isEnabled ? (configuration.isPressed ? T.accent.opacity(0.85) : T.accent) : T.fill2, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(T.fg)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(configuration.isPressed ? T.fill2 : T.fill, in: Capsule())
    }
}

/// 送出、記下這種小的主色按鈕
struct SendStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(isEnabled ? T.onAccent : T.fg3)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(isEnabled ? T.accent : T.fill2, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// 按下去縮一點（三個評分按鈕）
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 清單裡整列可按的那種
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? T.fill : Color.clear)
    }
}

/// 月曆左右切換的圓鈕
struct RoundIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(T.fg)
            .frame(width: 34, height: 34)
            .background(T.fill, in: Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.3)
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(PrimaryStyle())
            .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(SecondaryStyle())
    }
}

/// 灰字的文字按鈕（先不剝、改一下……）
struct TextLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(T.fg2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let title: String
    var pressed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(pressed ? T.bg : T.fg)
                .background(pressed ? T.fg : T.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }
}

struct MiniButton: View {
    let title: String
    var ghost = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(ghost ? T.fg : T.onAccent)
                .background(ghost ? T.fill : T.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(T.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(T.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 全頁 sheet 左上角的毛玻璃圓鈕
struct GlassButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(T.fg)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - 文字

struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title2.bold())
            .padding(.top, 28)
            .padding(.bottom, 10)
    }
}

struct GroupLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(T.fg2)
            .padding(EdgeInsets(top: 24, leading: 18, bottom: 6, trailing: 18))
    }
}

struct FootNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(T.fg2)
            .lineSpacing(2)
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 0, trailing: 18))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(T.sep)
            .frame(height: 0.5)
            .padding(.leading, 18)
    }
}

struct Quote: View {
    let k: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.footnote).foregroundStyle(T.fg2)
            Text(text).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(T.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct StatusTag: View {
    let text: String
    var pass = false

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(pass ? T.onAccent : T.fg2)
            .background(pass ? T.accent : T.fill, in: Capsule())
    }
}

/// 多行輸入（網頁版的 textarea.say）
struct SayField: View {
    @Binding var text: String
    var placeholder: String
    var lines = 3
    var font: Font = .title3

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(lines...max(lines, 8))
            .font(font)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 底部那條短訊息
struct ToastView: View {
    @Environment(Toaster.self) private var toaster

    var body: some View {
        ZStack {
            if let m = toaster.message {
                Text(m)
                    .font(.subheadline)
                    .foregroundStyle(T.bg)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(T.fg, in: Capsule())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: toaster.message)
        .allowsHitTesting(false)
    }
}

// MARK: - 四格

struct FourGrid: View {
    let c: FourCounts
    let kw: [String]
    let outcome: Rate

    var body: some View {
        let aN = c.ab + c.anb
        let nN = c.nab + c.nanb
        let pa = aN > 0 ? Int((Double(c.ab) / Double(aN) * 100).rounded()) : 0
        let pn = nN > 0 ? Int((Double(c.nab) / Double(nN) * 100).rounded()) : 0
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    cell("")
                    cell(outcome.rawValue)
                    cell("不是" + outcome.rawValue)
                }
                GridRow {
                    cell("有「" + kw.joined(separator: "／") + "」")
                    num(c.ab)
                    num(c.anb)
                }
                GridRow {
                    cell("沒有")
                    num(c.nab)
                    num(c.nanb)
                }
            }
            .background(T.sep)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("有的時段 \(c.ab)/\(aN)（\(pa)%）是「\(outcome.rawValue)」；沒有的時段 \(c.nab)/\(nN)（\(pn)%）。"
                 + (aN < 4 ? "有的時段太少，還不能判斷。" : ""))
                .font(.subheadline)
                .foregroundStyle(T.fg2)
        }
    }

    private func cell(_ s: String) -> some View {
        Text(s)
            .font(.footnote)
            .foregroundStyle(T.fg2)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(T.card)
    }

    private func num(_ n: Int) -> some View {
        Text("\(n)")
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(T.card)
    }
}

// MARK: - 會換行的 chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, x - spacing)
        }
        return CGSize(width: maxW == .infinity ? w : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
