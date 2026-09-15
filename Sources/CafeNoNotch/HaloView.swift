import SwiftUI
import Foundation

/// Geometria do notch (ou de uma "pílula" sintética em Macs sem notch).
struct NotchGeometry {
    var width: CGFloat        // largura do notch
    var height: CGFloat       // altura (≈ safeArea top)
    var cornerRadius: CGFloat // raio dos cantos de baixo
    var drawBody: Bool        // (legado) true em Macs sem notch

    /// Margem transparente ao redor, para o glow "vazar".
    var pad: CGFloat { 22 }

    /// Tamanho da ilha expandida (o fundo preto que "cresce") — mais horizontal.
    var expandedIslandWidth: CGFloat { max(width, 500) }
    // Deriva do conteúdo real: faixa do notch + conteúdo do café + rodapé.
    // Assim cabe justo em qualquer notch, sem cortar nem sobrar tarja.
    var expandedIslandHeight: CGFloat { height + 300 }
    var expandedCorner: CGFloat { 26 }

    var collapsedSize: CGSize {
        CGSize(width: width + pad * 2, height: height + pad)
    }
    var expandedSize: CGSize {
        CGSize(width: expandedIslandWidth + pad * 2, height: expandedIslandHeight + pad)
    }
}

/// Ilha. Recolhida: topo reto (colado na câmera), só a base arredondada.
/// Expandida (`topRounded`): retângulo com os quatro cantos arredondados.
struct IslandShape: Shape {
    var corner: CGFloat
    var topRounded: Bool = false
    var animatableData: CGFloat {
        get { corner }
        set { corner = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(corner, rect.height / 2, rect.width / 2)
        if topRounded {
            return Path(roundedRect: rect, cornerRadius: r)
        }
        var p = Path()
        let rb = min(corner, rect.height, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rb))
        p.addArc(center: CGPoint(x: rect.minX + rb, y: rect.maxY - rb), radius: rb,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX - rb, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.maxX - rb, y: rect.maxY - rb), radius: rb,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: CoffeeModel
    let geo: NotchGeometry

    @State private var breathing = false
    @State private var twinkle = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { model.phase != .sleeping }
    private var pomoActive: Bool { model.pomodoroActive }
    private var isHot: Bool { model.phase == .hot || model.phase == .warm }

    // Morph desacoplado: altura e largura animam separadamente.
    // Ao expandir, a ALTURA cresce primeiro (o preto "escorre" pra fora do notch,
    // ainda na largura da câmera) e a LARGURA abre logo depois — parece que o
    // card sai do quadrado preto. Ao recolher, o inverso.
    @State private var wf: CGFloat = 0   // fator de largura (0=notch, 1=card)
    @State private var hf: CGFloat = 0   // fator de altura

    private var islandW: CGFloat { geo.width + (geo.expandedIslandWidth - geo.width) * wf }
    private var islandH: CGFloat { geo.height + (geo.expandedIslandHeight - geo.height) * hf }
    private var corner: CGFloat { geo.cornerRadius + (geo.expandedCorner - geo.cornerRadius) * max(wf, hf) }

    var body: some View {
        VStack(spacing: 0) {
            island
                .scaleEffect(breathing ? 1.02 : 1.0, anchor: .top)
                // área clicável generosa quando recolhido (fácil acertar o notch)
                .frame(height: model.expanded ? nil : geo.collapsedSize.height, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { model.toggleExpanded() }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            wf = model.expanded ? 1 : 0
            hf = model.expanded ? 1 : 0
            startAnimations()
        }
        .onChange(of: isHot) { startAnimations() }
        .onChange(of: model.expanded) { _, exp in animateMorph(exp) }
    }

    private func animateMorph(_ exp: Bool) {
        startAnimations()
        // Mesma curva do lab: cubic-bezier(.22,.61,.36,1) — suave, sem mola.
        // Largura lidera; a altura entra com atraso. Mesma duração nos dois eixos.
        if exp {
            // infla os dois eixos JUNTOS a partir do notch (sai da própria ilha),
            // ease-out — nasce no ponto da câmera e cresce pra fora.
            let a = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.40)
            withAnimation(a) { wf = 1; hf = 1 }
        } else {
            // recolher (perfeito): fecha os lados, depois recolhe pra dentro.
            let a = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.38)
            withAnimation(a) { wf = 0 }
            withAnimation(a.delay(0.09)) { hf = 0 }
        }
    }

    // Recolhido: preto puro (funde com o notch). Expandido: obsidiana no card
    // inteiro (sem tarja preta no topo — só o recorte físico do notch fica preto).
    private var islandFill: LinearGradient {
        model.expanded
            ? LinearGradient(colors: [Color(red: 0.090, green: 0.090, blue: 0.102),
                                      Color(red: 0.039, green: 0.039, blue: 0.047)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            IslandShape(corner: corner, topRounded: model.expanded).fill(islandFill)

            // conteúdo sempre montado no tamanho final, recortado pela ilha:
            // conforme o preto cresce, ele "desenrola" de cima (câmera) pra baixo.
            DayPanel(model: model, islandWidth: geo.expandedIslandWidth)
                .frame(width: geo.expandedIslandWidth, height: geo.expandedIslandHeight - geo.height, alignment: .top)
                .padding(.top, geo.height + 2)
                .opacity(model.expanded ? 1 : 0)
                // preto infla primeiro; conteúdo entra logo depois
                .animation(.easeInOut(duration: 0.2).delay(model.expanded ? 0.14 : 0),
                           value: model.expanded)
        }
        .frame(width: islandW, height: islandH, alignment: .top)
        .clipShape(IslandShape(corner: corner, topRounded: model.expanded))
        .overlay(outline)
    }

    @ViewBuilder
    private var outline: some View {
        // Base café com leite sempre presente: é o que aparece nas metades
        // inativas (esquerda = café, direita = foco). Cada lado ativo é
        // sobreposto na sua cor, drenando do centro pra fora.
        let border = ZStack {
            // base preta: some nas metades inativas (vira parte da ilha).
            IslandShape(corner: corner, topRounded: model.expanded)
                .stroke(Color.black, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            if active {
                strokeRing(model.haloColor)
                    .mask(halfMask(fromRight: false))
                    .blur(radius: 0.6)
            }
            if pomoActive {
                strokeRing(model.pomodoroColor)
                    .mask(halfMask(fromRight: true))
                    .blur(radius: 0.6)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: model.haloColor)
        .animation(.easeInOut(duration: 0.5), value: model.heat)
        .animation(.easeInOut(duration: 0.5), value: model.pomodoroFraction)

        // expandido: sem borda/glow no topo (funde com a câmera).
        if model.expanded {
            border.mask(topFadeMask)
        } else {
            border
        }
    }

    /// Anel colorido (borda + glow) usado por café e foco. Um traço mais claro
    /// por cima pulsa (cintila) para dar vida e ficar mais visível.
    private func strokeRing(_ color: Color) -> some View {
        let shape = IslandShape(corner: corner, topRounded: model.expanded)
        return ZStack {
            shape
                .stroke(color.opacity(0.68), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                .shadow(color: color.opacity(0.60), radius: 9)
                .shadow(color: color.opacity(0.32), radius: 18)
            shape
                .stroke(color.opacity(twinkle ? 0.95 : 0.30),
                        style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                .blur(radius: 0.5)
        }
    }

    /// Máscara que revela só uma metade do anel, ancorada na borda EXTERNA e com
    /// comprimento proporcional à fração — assim o anel esvazia do centro pra
    /// fora. Uma transição suave na frente de drenagem + glow que vaza pra fora.
    /// Revela a metade inteira do anel (esquerda ou direita), com uma juntinha
    /// suave no centro e o glow vazando só pra fora — contorno sempre completo.
    private func halfMask(fromRight: Bool) -> some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let seam: CGFloat = 8   // transição suave na divisa central
            HStack(spacing: 0) {
                if fromRight {
                    Color.clear.frame(width: half - seam)
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: seam)
                    Color.black.frame(maxWidth: .infinity)
                } else {
                    Color.black.frame(maxWidth: .infinity)
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: seam)
                    Color.clear.frame(width: half - seam)
                }
            }
            .padding(.vertical, -80)
            .padding(fromRight ? .trailing : .leading, -80)
        }
    }

    /// Máscara que apaga o topo mas deixa o glow vazar pros lados e por baixo.
    private var topFadeMask: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(g.size.height * 0.4, geo.height + 10))
                Color.black
            }
            .padding(.horizontal, -80)   // não corta o glow lateral
            .padding(.bottom, -80)       // nem o de baixo
        }
    }

    private func startAnimations() {
        // respiração (só quando quente); o brilho viajante é dirigido por
        // TimelineView no contorno, então não precisa ser iniciado aqui.
        withAnimation(isHot && !reduceMotion
            ? .easeInOut(duration: 3.4).repeatForever(autoreverses: true)
            : .easeInOut(duration: 0.4)) {
            breathing = isHot && !reduceMotion
        }
        // cintilar contínuo do anel (mais visível), a menos que reduza movimento.
        withAnimation(reduceMotion
            ? .easeInOut(duration: 0.3)
            : .easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
            twinkle = !reduceMotion
        }
    }
}

// MARK: - Paleta do redesign (obsidiana + café + foco)

private enum Palette {
    static let ink   = Color(red: 0.957, green: 0.945, blue: 0.918) // #F4F1EA
    static let ink2  = Color(red: 0.659, green: 0.639, blue: 0.604) // #A8A39A
    static let ink3  = Color(red: 0.431, green: 0.416, blue: 0.380) // #6E6A61
    static let crema = Color(red: 0.906, green: 0.753, blue: 0.549) // #E7C08C
    static let panelTop = Color(red: 0.090, green: 0.090, blue: 0.102) // #17171A
    static let panelBot = Color(red: 0.039, green: 0.039, blue: 0.047) // #0A0A0C
    static let hair  = Color.white.opacity(0.06)
    static let track = Color.white.opacity(0.08)
}

/// Painel expandido. Três abas horizontais (dois dedos no trackpad):
/// "Café" (estado + histórico do dia, rolável), "Foco" (pomodoro) e "Sobre".
/// Mostradores circulares amarram o interior ao formato da câmera/halo.
struct DayPanel: View {
    @ObservedObject var model: CoffeeModel
    let islandWidth: CGFloat

    private var pageW: CGFloat { islandWidth - 44 }

    var body: some View {
        VStack(spacing: 12) {
            pager
            footer
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Pager: mostra exatamente a página ativa (conteúdo sempre em sincronia com
    // os pontinhos e o rodapé), com um slide leve na troca.
    private var pager: some View {
        ZStack(alignment: .topLeading) {
            currentPage
                .frame(width: pageW).frame(maxHeight: .infinity, alignment: .topLeading)
                .id(model.page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .frame(width: pageW).frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: model.page)
    }

    @ViewBuilder
    private var currentPage: some View {
        switch model.page {
        case 0:  cafePage
        case 1:  focoPage
        default: sobrePage
        }
    }

    // ── Aba "Café": estado em cima, histórico do dia embaixo (tudo visível) ─
    private var cafePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            stateRow
            historySection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)      // afasta o mostrador do topo (canto arredondado)
    }

    private var stateRow: some View {
        HStack(alignment: .top, spacing: 20) {
            heatGauge
                .padding(.leading, 18)   // afasta o mostrador da borda esquerda
            VStack(alignment: .leading, spacing: 0) {
                Text(model.phase.label)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(model.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
                    .padding(.top, 3)
                if model.phase != .sleeping {
                    VStack(spacing: 7) {
                        metaRow("feito", model.elapsedMinutes < 1
                                ? "agorinha"
                                : "há \(Int(model.elapsedMinutes.rounded())) min")
                        Rectangle().fill(Palette.hair).frame(height: 1)
                        metaRow("esfria de vez", coolLabel)
                    }
                    .padding(.top, 10)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var coolLabel: String {
        let left = CoffeeModel.coolMinutes - model.elapsedMinutes
        if left <= 0 { return "já esfriou" }
        return "em ~\(Int(left.rounded())) min"
    }

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12.5)).foregroundStyle(Palette.ink3)
            Spacer()
            Text(v).font(.system(size: 13.5)).foregroundStyle(Palette.ink)
        }
    }

    // Mostrador de calor: arco de 270° na cor da fase + temperatura no centro.
    private var heatGauge: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Palette.track, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * model.heat)
                .stroke(model.haloColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.5), value: model.heat)

            if model.phase == .hot || model.phase == .warm {
                SteamView().offset(y: -27)
            }

            if model.phase == .sleeping {
                Text("—").font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink3)
            } else {
                VStack(spacing: 0) {
                    Text("\(model.temperatureC)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.haloColor)
                    Text("°C")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink2)
                }
            }
        }
        .frame(width: 100, height: 100)
    }

    // ── Histórico do dia: contador + linha do tempo ──────────────────────
    private var historySection: some View {
        let times = model.todayTimes()
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Palette.hair).frame(height: 1).padding(.bottom, 12)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(times.count)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.crema)
                Text(times.isEmpty ? "nenhum café ainda"
                     : (times.count == 1 ? "café hoje" : "cafés hoje"))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
            }
            .padding(.bottom, times.isEmpty ? 6 : 12)

            if times.isEmpty {
                Text("faz o primeiro pra acender o halo")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink3)
            } else {
                TimelineStrip(times: times)
            }
        }
    }

    // ── Aba "Foco": anel de progresso + controles ────────────────────────
    private var focoTitle: String {
        switch model.pomodoroState {
        case .running: return "Foco"
        case .paused:  return "Pausado"
        case .idle:    return "Pomodoro"
        }
    }
    private var focoCenterSub: String {
        switch model.pomodoroState {
        case .running: return "no foco"
        case .paused:  return "pausado"
        case .idle:    return "pronto"
        }
    }
    private var endClock: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date().addingTimeInterval(model.pomodoroRemaining))
    }

    private var focoPage: some View {
        HStack(spacing: 22) {
            focusRing
                .padding(.leading, 18)   // afasta o anel da borda esquerda
            VStack(alignment: .leading, spacing: 0) {
                Text(focoTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(model.pomodoroSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
                    .padding(.top, 3)
                if model.pomodoroState == .idle {
                    presetsRow.padding(.top, 16)
                } else {
                    Text("termina \(endClock)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink3)
                        .padding(.top, 16)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var focusRing: some View {
        ZStack {
            Circle().stroke(Palette.track, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            Circle().trim(from: 0, to: model.pomodoroFraction)
                .stroke(model.pomodoroColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: model.pomodoroFraction)
            VStack(spacing: 2) {
                Text(model.pomodoroLabel)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.pomodoroColor)
                Text(focoCenterSub)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.ink3)
            }
        }
        .frame(width: 118, height: 118)
    }

    private var presetsRow: some View {
        HStack(spacing: 7) {
            Text("duração").font(.system(size: 12)).foregroundStyle(Palette.ink3)
            ForEach([15, 25, 30, 45, 50], id: \.self) { presetChip($0) }
        }
    }

    private func presetChip(_ m: Int) -> some View {
        let selected = Int(model.pomodoroMinutes) == m
        let tint = model.pomodoroColor
        return Button { model.setPomodoroMinutes(Double(m)) } label: {
            Text("\(m)")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? tint : Palette.ink2)
                .frame(minWidth: 24)
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(Capsule().fill(tint.opacity(selected ? 0.18 : 0.05)))
                .overlay(Capsule().stroke(tint.opacity(selected ? 0.5 : 0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // ── Aba "Sobre" ──────────────────────────────────────────────────────
    private var sobrePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(AppInfo.name)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(AppInfo.version)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.crema)
            }

            if let t = model.updateTag {
                linkButton("nova versão \(t) disponível", AppInfo.releasesURL,
                           color: model.pomodoroColor, weight: .medium)
            } else {
                Text("Você está na última versão.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
            }

            HStack {
                Text("atalho para registrar um café")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Text(model.hotKeyLabel)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.hair, lineWidth: 1))
            }
            .padding(.top, 4)

            HStack(spacing: 18) {
                actionButton("configurar", color: model.pomodoroColor) {
                    NotificationCenter.default.post(name: .openCafeSettings, object: nil)
                }
                linkButton("ver no GitHub", AppInfo.repoURL, color: model.pomodoroColor, weight: .regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func actionButton(_ text: String, color: Color,
                              weight: Font.Weight = .regular, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: weight)).foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func linkButton(_ text: String, _ urlString: String,
                            color: Color, weight: Font.Weight) -> some View {
        Button {
            if let u = URL(string: urlString) { NSWorkspace.shared.open(u) }
        } label: {
            Text(text).font(.system(size: 13, weight: weight)).foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // ── Rodapé: pontinhos + ações contextuais por aba ────────────────────
    private var footer: some View {
        HStack(spacing: 12) {
            dots
            Spacer()
            footerActions
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        switch model.page {
        case 0:
            coffeePrimaryButton
            FooterButton(title: "acabou o café") { model.reset() }
        case 1:
            focoPrimaryButton
            if model.pomodoroState != .idle {
                FooterButton(title: "zerar") { model.resetPomodoro() }
            }
        default:
            FooterButton(title: "Sair") { NSApp.terminate(nil) }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(model.page == i ? 0.92 : 0.24))
                    .frame(width: model.page == i ? 18 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: model.page)
                    .onTapGesture { model.setPage(i) }
            }
        }
    }

    private var coffeePrimaryButton: some View {
        Button(action: { model.brew() }) {
            Text("Fiz um café")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(
                    LinearGradient(colors: [Palette.crema, Color(red: 0.839, green: 0.651, blue: 0.404)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .foregroundStyle(Color(red: 0.141, green: 0.090, blue: 0.012))
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private var focoPrimaryButton: some View {
        let title: String = {
            switch model.pomodoroState {
            case .idle:    return "iniciar"
            case .running: return "pausar"
            case .paused:  return "retomar"
            }
        }()
        return Button(action: { model.togglePomodoro() }) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(model.pomodoroColor)
                .foregroundStyle(Color(red: 0.02, green: 0.06, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

/// Fumacinha subindo do café (só quando quente).
struct SteamView: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let heights: [CGFloat] = [16, 22, 16]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.34)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(width: 3, height: heights[i])
                    .offset(y: on ? -7 : 6)
                    .opacity(on ? 0 : 0.55)
                    .animation(reduceMotion ? .default
                               : .easeInOut(duration: 2.2).repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.5),
                               value: on)
            }
        }
        .frame(height: 24)
        .onAppear { if !reduceMotion { on = true } }
    }
}

/// Linha do tempo dos cafés de hoje (cronológica). Ponto branco = o mais recente.
struct TimelineStrip: View {
    let times: [Date]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let xs = spacedX(width: w)
            ZStack(alignment: .topLeading) {
                Text("manhã").font(.system(size: 10.5)).foregroundStyle(Palette.ink3)
                    .offset(x: 2, y: 0)
                Text("agora").font(.system(size: 10.5)).foregroundStyle(Palette.ink3)
                    .frame(width: 44, alignment: .trailing).offset(x: w - 46, y: 0)

                Capsule().fill(Color.white.opacity(0.09))
                    .frame(width: w, height: 2).offset(x: 0, y: 22)

                ForEach(Array(xs.enumerated()), id: \.offset) { idx, x in
                    let last = idx == xs.count - 1
                    let color = last ? Color.white : Palette.crema
                    ZStack {
                        Circle().fill(color.opacity(0.18)).frame(width: 20, height: 20)
                        Circle().fill(color).frame(width: 11, height: 11)
                    }
                    .offset(x: x - 10, y: 12)
                }
            }
        }
        .frame(height: 34)
    }

    /// Posições x dos pontos: proporcionais ao horário, mas com um gap mínimo
    /// entre pontos, pra que cafés próximos no tempo não fiquem um sobre o outro.
    private func spacedX(width w: CGFloat) -> [CGFloat] {
        guard !times.isEmpty else { return [] }
        let cal = Calendar.current
        let now = Date()
        // Janela do dia: "manhã" (6h) → "agora". Se houver café antes das 6h,
        // a janela estica pra incluí-lo. Assim cada ponto cai no horário real.
        let morning = cal.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? cal.startOfDay(for: now)
        let start = min(morning, times.first ?? morning)
        let span = max(60, now.timeIntervalSince(start))
        let minGap: CGFloat = 15
        var xs = times.map { CGFloat($0.timeIntervalSince(start) / span) * (w - 14) + 7 }
        for i in 1..<xs.count where xs[i] < xs[i - 1] + minGap {
            xs[i] = xs[i - 1] + minGap
        }
        if let lastX = xs.last, lastX > w - 7 {
            let shift = lastX - (w - 7)
            for i in xs.indices { xs[i] -= shift }
        }
        return xs
    }
}

struct FooterButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
}
