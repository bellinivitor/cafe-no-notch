import SwiftUI
import AppKit

extension Notification.Name {
    static let openCafeSettings = Notification.Name("openCafeSettings")
}

/// Janela de configurações (padrão Overseer): por enquanto, o atalho global.
struct SettingsView: View {
    @ObservedObject var model: CoffeeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configurações")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Atalho global para registrar um café")
                    .font(.callout)
                Text("Funciona de qualquer app. Deixe vazio para não usar atalho (padrão).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HotKeyRecorder(model: model)
            }

            Spacer()

            Text("As preferências ficam salvas automaticamente.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380, height: 190)
    }
}

/// Grava um atalho: clique em "Definir" e pressione a combinação (com ao menos
/// um modificador). Funciona porque esta janela é comum e vira key window.
struct HotKeyRecorder: View {
    @ObservedObject var model: CoffeeModel
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Text(recording ? "aperte a combinação…" : model.hotKeyLabel)
                .font(.system(.body, design: .rounded)).bold()
                .frame(minWidth: 110, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))

            Button(recording ? "Cancelar" : "Definir") { toggle() }

            if !recording && model.hotKeyCode != 0 {
                Button("Tirar") { model.updateHotKey(keyCode: 0, mods: 0, char: "") }
            }
        }
        .onDisappear { stop() }
    }

    private func toggle() {
        if recording { stop(); return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { return event }   // exige ao menos um modificador
            let ch = (event.charactersIgnoringModifiers ?? "").uppercased()
            model.updateHotKey(keyCode: UInt32(event.keyCode), mods: mods, char: ch)
            stop()
            return nil   // consome o evento
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
