import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    var opaqueBackground = false

    private var tint: Color { model.isLocked ? .orange : .accentColor }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 34)
            emblem
            Spacer().frame(height: 26)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 24)
            if model.isLocked {
                // Курсор после «Старт» остаётся прямо на кнопке, и тряпка легко «тапнет» по трекпаду.
                // Поэтому разблокировка — только удержанием.
                HoldToConfirmButton(title: buttonTitle, tint: tint, duration: 0.8, action: model.unlock)
            } else {
                Button(buttonTitle, action: model.primaryAction)
                    .buttonStyle(PillButtonStyle(tint: tint))
                    .focusable(false)
            }
            Text(footer)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(model.secureInputActive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(width: 360, height: 460)
        .background {
            if opaqueBackground {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectBackground().ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.isLocked)
    }

    private var emblem: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 128, height: 128)
                .overlay {
                    Image(systemName: "keyboard")
                        .font(.system(size: 54, weight: .regular))
                        .foregroundStyle(tint)
                }
            Image(systemName: model.isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(tint))
                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 3))
        }
    }

    private var title: String {
        if !model.hasPermission { return "Нужно разрешение" }
        return model.isLocked ? "Клавиатура заблокирована" : "Клавиатура включена"
    }

    private var subtitle: String {
        if !model.hasPermission { return "Включите KeyClean в разделе «Универсальный доступ», чтобы программа могла отключать клавиши." }
        return model.isLocked
            ? "Можно протирать клавиши. Когда закончите, зажмите кнопку трекпадом на секунду."
            : "Нажмите кнопку и протрите клавиатуру влажной салфеткой. Трекпад продолжит работать."
    }

    private var buttonTitle: String {
        if !model.hasPermission { return "Дать разрешение" }
        return model.isLocked ? "Удерживайте, чтобы включить" : "Старт"
    }

    private var footer: String {
        if !model.hasPermission { return "Нужно сделать один раз" }
        guard model.isLocked else { return "Кнопка питания не блокируется" }
        if model.secureInputActive { return "Другая программа включила защищённый ввод — клавиши могут проходить" }
        return String(format: "Включится сама через %d:%02d", model.secondsLeft / 60, model.secondsLeft % 60)
    }
}

struct PillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Срабатывает, только если кнопку держат нажатой `duration` секунд; заливка показывает прогресс.
struct HoldToConfirmButton: View {
    let title: String
    let tint: Color
    let duration: Double
    let action: () -> Void
    @State private var progress: CGFloat = 0

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(tint.opacity(0.55))
            GeometryReader { geo in
                Rectangle().fill(tint).frame(width: geo.size.width * progress)
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .clipShape(shape)
        .contentShape(shape)
        .scaleEffect(progress > 0 ? 0.98 : 1)
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
            action()
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: duration) : .easeOut(duration: 0.2)) {
                progress = pressing ? 1 : 0
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
