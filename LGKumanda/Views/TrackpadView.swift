import SwiftUI
import UIKit

struct TouchPad: View {
    @EnvironmentObject private var client: TVClient
    @AppStorage("cursorless") private var storedCursorless = true
    @AppStorage("browserUsesPointerV2") private var browserUsesPointer = false
    var forceCursorless = false
    /// Pointer mode regardless of settings, e.g. to tick a site's verification box once.
    var forceMouse = false
    /// Overrides the quiet (jumping) pointer setting when not nil.
    var quietOverride: Bool? = nil
    /// Web pages only highlight links under the real pointer, so the browser uses mouse mode unless the user turns that off.
    private var cursorless: Bool {
        if forceMouse { return false }
        if forceCursorless { return true }
        if client.isBrowserActive && browserUsesPointer { return false }
        return storedCursorless
    }
    @AppStorage("pointerSensitivity") private var sensitivity = 0.8
    @AppStorage("quietPointer") private var quietPointer = true
    private var quiet: Bool { !cursorless && (quietOverride ?? quietPointer) }
    var body: some View {
        TrackpadSurface(cursorless: cursorless, quiet: quiet, sensitivity: sensitivity,
                        move: { client.movePointer(dx: $0, dy: $1) },
                        jump: { client.jumpPointer(dx: $0, dy: $1) },
                        key: { client.key($0) },
                        click: { client.pointerMessage("type:click\n\n") },
                        scroll: { client.pointerMessage("type:scroll\ndx:0\ndy:\($0)\n\n") },
                        ended: { client.stopPointerMotion() })
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: cursorless ? "hand.draw" : "cursorarrow.motionlines").font(.title).foregroundStyle(Theme.accent)
                    Text(cursorless ? "Kaydır ve seç" : quiet ? "Sessiz fare" : "Dokunmatik fare").font(.headline)
                    Text(cursorless ? "Kaydır: yön tuşları\nDokun: OK" : quiet ? "Kaydır ve bırak: işaretçi atlar\nİki parmak: kaydır\nDokun: tıkla" : "Tek parmak: hareket\nİki parmak: kaydır\nDokun: tıkla")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(8).allowsHitTesting(false).accessibilityHidden(true)
            }
            .accessibilityLabel(cursorless ? "İşaretçisiz gezinme alanı" : "Dokunmatik fare alanı")
            .accessibilityAction(named: "Yukarı") { client.key(.up) }
            .accessibilityAction(named: "Aşağı") { client.key(.down) }
            .accessibilityAction(named: "Sol") { client.key(.left) }
            .accessibilityAction(named: "Sağ") { client.key(.right) }
            .accessibilityAction(named: "Seç") {
                if cursorless { client.key(.enter) } else { client.pointerMessage("type:click\n\n") }
            }
            .onDisappear { client.stopPointerMotion() }
    }
}

struct PointerModePicker: View {
    @EnvironmentObject private var client: TVClient
    @AppStorage("cursorless") private var cursorless = true
    @AppStorage("browserUsesPointerV2") private var browserUsesPointer = false
    @AppStorage("quietPointer") private var quietPointer = true
    private var mouseActive: Bool { (client.isBrowserActive && browserUsesPointer) || !cursorless }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if client.isBrowserActive && browserUsesPointer {
                Text("Web tarayıcısı: fare kullanılıyor. İşaretçisiz gezinmek için bağlantıları Klavye sekmesindeki web adresi ekranından telefonda seç.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Dokunmatik alanın davranışı", selection: $cursorless) {
                    Text("İşaretçisiz").tag(true)
                    Text("Fare").tag(false)
                }.pickerStyle(.segmented)
            }
            if client.isBrowserActive {
                Toggle("Web'de fare kullan", isOn: $browserUsesPointer).font(.subheadline)
                    .accessibilityIdentifier("browserUsesPointer")
            }
            if mouseActive {
                Toggle("Sessiz fare: işaretçi kaymadan atlar", isOn: $quietPointer).font(.subheadline)
                    .accessibilityIdentifier("quietPointer")
            }
        }
    }
}

private struct TrackpadSurface: UIViewRepresentable {
    let cursorless: Bool
    let quiet: Bool
    let sensitivity: Double
    let move: (Int, Int) -> Void
    let jump: (Int, Int) -> Void
    let key: (RemoteKey) -> Void
    let click: () -> Void
    let scroll: (Int) -> Void
    let ended: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isMultipleTouchEnabled = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
        let twoFinger = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scroll(_:)))
        twoFinger.minimumNumberOfTouches = 2; twoFinger.maximumNumberOfTouches = 2
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.require(toFail: pan); tap.require(toFail: twoFinger)
        view.addGestureRecognizer(pan); view.addGestureRecognizer(twoFinger); view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = context.environment.isEnabled
        if context.coordinator.parent.cursorless != cursorless || context.coordinator.parent.quiet != quiet {
            context.coordinator.reset(); ended()
        }
        context.coordinator.parent = self
    }
    final class Coordinator: NSObject {
        var parent: TrackpadSurface
        var filter = PointerDeltaFilter()
        var navigation = CGPoint.zero
        var scrollDistance: CGFloat = 0
        var lastKey = Date.distantPast
        var jumpTarget = CGPoint.zero
        init(_ parent: TrackpadSurface) { self.parent = parent }
        func reset() { filter = PointerDeltaFilter(); navigation = .zero; scrollDistance = 0; lastKey = .distantPast; jumpTarget = .zero }
        @objc func tap() {
            if parent.cursorless { parent.key(.enter) } else { parent.click() }
        }
        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began { reset() }
            if recognizer.state == .began || recognizer.state == .changed {
                let delta = recognizer.translation(in: recognizer.view)
                recognizer.setTranslation(.zero, in: recognizer.view)
                if parent.cursorless {
                    navigation.x += delta.x; navigation.y += delta.y
                    if max(abs(navigation.x), abs(navigation.y)) >= 28, Date().timeIntervalSince(lastKey) >= 0.13 {
                        if abs(navigation.x) > abs(navigation.y) { parent.key(navigation.x > 0 ? .right : .left) }
                        else { parent.key(navigation.y > 0 ? .down : .up) }
                        navigation = .zero; lastKey = Date()
                    }
                } else if parent.quiet {
                    let gain = max(0.2, min(2, parent.sensitivity)) * 0.8
                    jumpTarget.x += delta.x * gain; jumpTarget.y += delta.y * gain
                } else {
                    let step = filter.move(dx: delta.x, dy: delta.y, gain: parent.sensitivity)
                    if step.0 != 0 || step.1 != 0 { parent.move(step.0, step.1) }
                }
            }
            if recognizer.state == .ended, parent.quiet, !parent.cursorless {
                parent.jump(Int(jumpTarget.x.rounded()), Int(jumpTarget.y.rounded()))
            }
            if [.ended, .cancelled, .failed].contains(recognizer.state) { reset(); parent.ended() }
        }
        @objc func scroll(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began { reset(); parent.ended() }
            let delta = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)
            scrollDistance += delta.y
            if abs(scrollDistance) >= 18 {
                let direction = scrollDistance > 0 ? -1 : 1
                if parent.cursorless { parent.key(direction > 0 ? .down : .up) }
                else { parent.scroll(direction) }
                scrollDistance = 0
            }
            if [.ended, .cancelled, .failed].contains(recognizer.state) { reset() }
        }
    }
}
