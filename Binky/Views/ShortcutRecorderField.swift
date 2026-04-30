import AppKit
import SwiftUI

/// Records a menu-bar style shortcut (Command required). See `CustomShortcut.from(event:)`.
///
/// The field stays passive until `isRecording` flips to `true` (driven by a parent “Edit” button).
/// While recording: any valid combo saves; Esc cancels; Delete resets to default.
struct ShortcutRecorderField: NSViewRepresentable {
    @ObservedObject var prefs: BinkyPreferences
    let action: ShortcutAction
    @Binding var isRecording: Bool
    @Binding var inlineError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let v = ShortcutRecorderNSView()
        v.coordinator = context.coordinator
        context.coordinator.view = v
        return v
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        let s = prefs.shortcut(for: action)
        nsView.syncRecordingState(isRecording: isRecording, current: s)
    }

    final class Coordinator {
        var parent: ShortcutRecorderField
        weak var view: ShortcutRecorderNSView?

        init(_ parent: ShortcutRecorderField) {
            self.parent = parent
        }

        func handleCapturedShortcut(_ shortcut: CustomShortcut) {
            let conflict = ShortcutValidator.conflict(for: shortcut, assigningTo: parent.action, in: parent.prefs)
            switch conflict {
            case .some(.internalCollision(let otherTitle)):
                parent.inlineError = "\(S.shortcutsConflictPrefix) \(otherTitle)"
                view?.flashReject()
            case .some(.systemReserved), nil:
                parent.inlineError = nil
                parent.prefs.setShortcut(shortcut, for: parent.action)
                parent.isRecording = false
            }
        }

        func resetToDefault() {
            parent.inlineError = nil
            parent.prefs.resetShortcut(parent.action)
            parent.isRecording = false
        }

        func cancelListening() {
            parent.inlineError = nil
            parent.isRecording = false
        }
    }
}

// MARK: - AppKit view

final class ShortcutRecorderNSView: NSView {
    weak var coordinator: ShortcutRecorderField.Coordinator?

    private let field: NSTextField
    private var eventMonitor: Any?
    private var listening = false

    /// The view itself is not focusable — focus stays on the parent UI; recording is driven from the parent button.
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        field = NSTextField(labelWithString: "")
        field.alignment = .center
        field.font = .systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        super.init(frame: frameRect)
        addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        applyIdleStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func syncRecordingState(isRecording: Bool, current: CustomShortcut) {
        if isRecording {
            if !listening { startListening() }
        } else {
            if listening { stopMonitor(); listening = false }
            applyIdleStyle()
            field.stringValue = current.displayString
        }
    }

    func flashReject() {
        guard let layer = layer else { return }
        let prev = layer.backgroundColor
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            layer.backgroundColor = NSColor.systemRed.withAlphaComponent(0.25).cgColor
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.listening else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                layer.backgroundColor = prev
            }
        }
    }

    private func applyIdleStyle() {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    private func applyRecordingStyle() {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
    }

    private func startListening() {
        listening = true
        applyRecordingStyle()
        field.stringValue = S.shortcutsRecorderPrompt
        installMonitor()
    }

    private func installMonitor() {
        stopMonitor()
        guard let window = window else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard self.listening else { return event }
            guard event.window == window else { return event }

            if event.type == .keyDown {
                if event.keyCode == 53 { // Esc
                    self.coordinator?.cancelListening()
                    return nil
                }
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.coordinator?.resetToDefault()
                    return nil
                }
                if let s = CustomShortcut.from(event: event) {
                    self.coordinator?.handleCapturedShortcut(s)
                    return nil
                }
            }
            return event
        }
    }

    private func stopMonitor() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }

    deinit {
        stopMonitor()
    }
}
