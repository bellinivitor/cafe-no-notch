import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CoffeeModel()
    private var notch: NotchController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.startTicking()
        notch = NotchController(model: model)
        setupHotKey()

        // Debug: `--brew` acende o halo já no lançamento (para testes/screenshots).
        if CommandLine.arguments.contains("--brew") {
            model.brew()
        }
    }

    private func setupHotKey() {
        // ⌘⇧C: registra "fiz café agora".
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_C),
                        modifiers: UInt32(cmdKey) | UInt32(shiftKey)) { [weak self] in
            self?.model.brew()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // sem ícone no Dock nem na barra de menus
app.run()
