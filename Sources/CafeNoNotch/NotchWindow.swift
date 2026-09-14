import AppKit
import SwiftUI
import Combine

/// Onde e de que tamanho a janela fica, recolhida ou expandida.
struct NotchLayout {
    let screen: NSScreen
    let geo: NotchGeometry
    let centerX: CGFloat

    func frame(expanded: Bool) -> NSRect {
        let size = expanded ? geo.expandedSize : geo.collapsedSize
        let x = centerX - size.width / 2
        let y = screen.frame.maxY - size.height   // colado no topo da tela
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// Descobre a geometria do notch da tela (ou define uma pílula sintética).
func currentLayout() -> NotchLayout {
    let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        ?? NSScreen.main
        ?? NSScreen.screens[0]

    let topInset = screen.safeAreaInsets.top
    if topInset > 0,
       let left = screen.auxiliaryTopLeftArea,
       let right = screen.auxiliaryTopRightArea {
        let width = max(120, right.minX - left.maxX)
        let centerX = (left.maxX + right.minX) / 2
        let geo = NotchGeometry(width: width, height: topInset,
                                cornerRadius: min(9, topInset * 0.5), drawBody: false)
        return NotchLayout(screen: screen, geo: geo, centerX: centerX)
    }
    // Sem notch físico: pílula preta centralizada no topo.
    let geo = NotchGeometry(width: 200, height: 32, cornerRadius: 12, drawBody: true)
    return NotchLayout(screen: screen, geo: geo, centerX: screen.frame.midX)
}

/// Dona da janela do notch: cria, reposiciona, expande/recolhe.
final class NotchController {
    private let model: CoffeeModel
    private var panel: NSPanel!
    private var hosting: NSHostingView<IslandView>!
    private var layout: NotchLayout
    private var globalMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAccum: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()

    init(model: CoffeeModel) {
        self.model = model
        self.layout = currentLayout()
        build()

        // Expande/recolhe conforme o modelo.
        model.$expanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] v in self?.applyExpanded(v) }
            .store(in: &cancellables)

        // Clicar fora recolhe o painel.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.model.setExpanded(false)
        }

        // Swipe de dois dedos (scroll horizontal) troca de aba quando expandido.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.model.expanded else { return event }
            if event.phase == .began { self.scrollAccum = 0 }
            // só reage a gesto horizontal (não atrapalha o scroll vertical da lista)
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                self.scrollAccum += event.scrollingDeltaX
                if abs(self.scrollAccum) > 42 {
                    let dir = self.scrollAccum < 0 ? 1 : -1   // arrastar p/ esquerda = próxima aba
                    let target = self.model.page + dir
                    DispatchQueue.main.async { self.model.setPage(target) }
                    self.scrollAccum = 0
                }
            }
            if event.phase == .ended || event.phase == .cancelled { self.scrollAccum = 0 }
            return event
        }

        // Reposiciona se a configuração de telas mudar.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }

    private func build() {
        let frame = layout.frame(expanded: model.expanded)
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false          // clicável (o halo mora sobre o notch)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: IslandView(model: model, geo: layout.geo))
        host.sizingOptions = []   // não deixa o SwiftUI redimensionar a janela sozinho
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        self.hosting = host
        panel.orderFrontRegardless()
    }

    private func rebuild() {
        panel?.close()
        cancellables.removeAll()
        layout = currentLayout()
        build()
        model.$expanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] v in self?.applyExpanded(v) }
            .store(in: &cancellables)
    }

    private func applyExpanded(_ expanded: Bool) {
        if expanded {
            // cresce a janela primeiro; o card entra com a transição do SwiftUI.
            let f = layout.frame(expanded: true)
            hosting.frame = NSRect(origin: .zero, size: f.size)
            panel.setFrame(f, display: true)
        } else {
            // deixa a ilha encolher (morph) antes de reduzir a janela.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.model.expanded else { return }
                let f = self.layout.frame(expanded: false)
                self.panel.setFrame(f, display: true)
                self.hosting.frame = NSRect(origin: .zero, size: f.size)
            }
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }
}
