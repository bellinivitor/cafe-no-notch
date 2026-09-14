import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CoffeeModel()
    private var notch: NotchController?
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.startTicking()
        model.requestNotificationAuth()
        notch = NotchController(model: model)

        // Registra/atualiza o atalho global conforme a configuração.
        // Padrão: nenhum atalho (keyCode 0) — nada é registrado.
        Publishers.CombineLatest(model.$hotKeyCode, model.$hotKeyMods)
            .receive(on: RunLoop.main)
            .sink { [weak self] code, mods in self?.applyHotKey(code: code, mods: mods) }
            .store(in: &cancellables)

        // Botão "configurar" no card abre a janela de configurações.
        NotificationCenter.default.addObserver(
            forName: .openCafeSettings, object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }

        // Debug: `--brew` acende o halo já no lançamento (para testes/screenshots).
        if CommandLine.arguments.contains("--brew") {
            model.brew()
        }
    }

    private func applyHotKey(code: UInt32, mods: UInt32) {
        hotKey = nil                       // libera o anterior (deinit desregistra)
        guard code != 0 else { return }    // sem atalho definido
        hotKey = HotKey(keyCode: code, modifiers: mods) { [weak self] in
            self?.model.brew()
        }
    }

    private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Café no Notch"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // sem ícone no Dock nem na barra de menus
app.run()
