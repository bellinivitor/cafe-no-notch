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
    var expandedIslandHeight: CGFloat { 238 }
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

    private var island: some View {
        ZStack(alignment: .top) {
            IslandShape(corner: corner, topRounded: model.expanded).fill(Color.black)

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

/// Conteúdo do painel do dia — abas horizontais (dois dedos no trackpad):
/// "Agora" (estado do café) e "Cafés hoje" (lista). Botão fixo embaixo.
struct DayPanel: View {
    @ObservedObject var model: CoffeeModel
    let islandWidth: CGFloat

    // largura FIXA de cada aba = padrão único (ilha - padding horizontal).
    private var pageW: CGFloat { islandWidth - 40 }
    private let pagerH: CGFloat = 130   // altura fixa das abas
    private let coffeeInk = Color(red: 0.86, green: 0.66, blue: 0.46)

    var body: some View {
        VStack(spacing: 10) {
            // pager MANUAL: HStack de 2 abas de largura fixa, deslocada por índice
            // e recortada — determinístico, sem vazamento nem descalibragem.
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    agoraPage.frame(width: pageW, height: pagerH, alignment: .topLeading)
                    focoPage.frame(width: pageW, height: pagerH, alignment: .topLeading)
                    hojePage.frame(width: pageW, height: pagerH, alignment: .topLeading)
                    sobrePage.frame(width: pageW, height: pagerH, alignment: .topLeading)
                }
                .offset(x: -CGFloat(model.page) * pageW)
                .animation(.easeInOut(duration: 0.3), value: model.page)
            }
            .frame(width: pageW, height: pagerH, alignment: .topLeading)
            .clipped()

            // rodapé fixo: indicador de abas + ações (contextuais por aba).
            HStack(spacing: 12) {
                dots
                Spacer()
                if model.page == 1 {
                    focoPrimaryButton
                    if model.pomodoroState != .idle {
                        FooterButton(title: "zerar") { model.resetPomodoro() }
                    }
                } else {
                    coffeePrimaryButton
                    FooterButton(title: "acabou o café") { model.reset() }
                }
                FooterButton(title: "Sair") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(model.page == i ? 0.9 : 0.28))
                    .frame(width: 7, height: 7)
                    .onTapGesture { model.setPage(i) }
            }
        }
    }

    // ── Aba "Agora": estado do café ──────────────────────────────────────
    private var agoraPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(model.phase == .sleeping ? "☕︎" : emoji)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.phase.label)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 14)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(model.temperatureC)")
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .foregroundStyle(model.haloColor)
                Text("°")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(model.haloColor.opacity(0.85))
                Spacer()
                Text(model.elapsedMinutes < 1
                     ? "agorinha"
                     : "faz \(Int(model.elapsedMinutes.rounded())) min")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 12)

            HeatFocusBar(model: model)
        }
    }

    // ── Aba "Foco": cronômetro de pomodoro ───────────────────────────────
    private var focoTitle: String {
        switch model.pomodoroState {
        case .running: return "Foco"
        case .paused:  return "Pausado"
        case .idle:    return "Pomodoro"
        }
    }

    @ViewBuilder
    private var focoPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("⏳").font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(focoTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.pomodoroSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.pomodoroLabel)
                    .font(.system(size: 40, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.pomodoroColor)
                Spacer()
                Text("\(Int(model.pomodoroMinutes)) min")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 12)

            if model.pomodoroState == .idle {
                HStack(spacing: 7) {
                    Text("duração")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.4))
                    ForEach([15, 25, 30, 45, 50], id: \.self) { presetChip($0) }
                    Text("min")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            } else {
                HeatFocusBar(model: model)
            }
        }
    }

    // Botão primário do café (mesmo do rodapé antigo).
    private var coffeePrimaryButton: some View {
        Button(action: { model.brew() }) {
            Text("☕ Fiz um café")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [Color(red: 0.89, green: 0.65, blue: 0.42),
                                            Color(red: 0.78, green: 0.55, blue: 0.35)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .foregroundStyle(Color(red: 0.10, green: 0.07, blue: 0.02))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    // Botão primário do foco — mesmo lugar/porte do "Fiz um café".
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
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(model.pomodoroColor)
                .foregroundStyle(Color(red: 0.05, green: 0.06, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func presetChip(_ m: Int) -> some View {
        let selected = Int(model.pomodoroMinutes) == m
        let tint = model.pomodoroColor
        return Button { model.setPomodoroMinutes(Double(m)) } label: {
            Text("\(m)")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? tint : .white.opacity(0.6))
                .frame(minWidth: 26)
                .padding(.vertical, 5).padding(.horizontal, 6)
                .background(Capsule().fill(tint.opacity(selected ? 0.18 : 0.06)))
                .overlay(Capsule().stroke(tint.opacity(selected ? 0.5 : 0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // ── Aba "Cafés hoje": lista com espaço ───────────────────────────────
    private var hojePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cafés hoje")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(model.todayLabels().count)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.haloColor)
            }

            let labels = model.todayLabels()
            if labels.isEmpty {
                Text("nada ainda — faz o primeiro")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                // mostra os que cabem (3 colunas x 2 linhas); o resto vira "+N".
                FlowChips(labels: Array(labels.prefix(6)), accent: model.haloColor, columns: 3)
                if labels.count > 6 {
                    Text("+\(labels.count - 6) mais cedo")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
    }

    // ── Aba "Sobre": versão + atualização, no padrão do app ──────────────
    private var sobrePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AppInfo.name)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                Text(AppInfo.version)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(coffeeInk)
            }

            if let t = model.updateTag {
                linkButton("nova versão \(t) disponível", AppInfo.releasesURL,
                           color: model.haloColor, weight: .medium)
            } else {
                Text("está na última versão")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text("atalho")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                Text(model.hotKeyLabel)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                actionButton("configurar", color: coffeeInk) {
                    NotificationCenter.default.post(name: .openCafeSettings, object: nil)
                }
            }

            linkButton("ver no GitHub", AppInfo.repoURL, color: coffeeInk, weight: .medium)
        }
    }

    private func actionButton(_ text: String, color: Color,
                              weight: Font.Weight = .medium, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 12.5, weight: weight)).foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func linkButton(_ text: String, _ urlString: String,
                            color: Color, weight: Font.Weight) -> some View {
        Button {
            if let u = URL(string: urlString) { NSWorkspace.shared.open(u) }
        } label: {
            Text(text)
                .font(.system(size: 12.5, weight: weight))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private var emoji: String {
        switch model.phase {
        case .hot, .warm: return "☕️"
        case .cooling:    return "🌡️"
        case .cold:       return "☠️"
        case .sleeping:   return "☕︎"
        }
    }
}

/// Barra de progresso compartilhada. Com café E foco ativos, divide-se ao meio:
/// metade esquerda = calor do café, metade direita = foco restante. Com só um
/// ativo, ocupa a barra inteira na cor correspondente.
struct HeatFocusBar: View {
    @ObservedObject var model: CoffeeModel

    private var coffeeActive: Bool { model.phase != .sleeping }
    private var pomoActive: Bool { model.pomodoroActive }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let half = w / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))

                if coffeeActive && pomoActive {
                    // café: nasce no centro e cresce pra esquerda (ponta esvazia).
                    let coffeeLen = half * model.heat
                    RoundedRectangle(cornerRadius: 3).fill(model.haloColor)
                        .frame(width: max(3, coffeeLen))
                        .offset(x: half - coffeeLen)
                        .animation(.easeInOut(duration: 0.5), value: model.heat)
                    // foco: nasce no centro e cresce pra direita (ponta esvazia).
                    RoundedRectangle(cornerRadius: 3).fill(model.pomodoroColor)
                        .frame(width: max(0, half * model.pomodoroFraction))
                        .offset(x: half)
                        .animation(.easeInOut(duration: 0.5), value: model.pomodoroFraction)
                    // divisa central.
                    Rectangle().fill(Color.black.opacity(0.45))
                        .frame(width: 1).offset(x: half - 0.5)
                } else if pomoActive {
                    Capsule().fill(model.pomodoroColor)
                        .frame(width: max(6, w * model.pomodoroFraction))
                        .animation(.easeInOut(duration: 0.5), value: model.pomodoroFraction)
                } else {
                    Capsule().fill(model.haloColor)
                        .frame(width: max(6, w * model.heat))
                        .animation(.easeInOut(duration: 0.5), value: model.heat)
                }
            }
        }
        .frame(height: 6)
    }
}

struct FooterButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Chips de horário em grade não-lazy (renderiza dentro de ScrollView).
struct FlowChips: View {
    let labels: [String]
    let accent: Color
    var columns: Int = 2

    private let coffee = Color(red: 0.78, green: 0.55, blue: 0.35)
    private let coffeeInk = Color(red: 0.88, green: 0.70, blue: 0.50)

    var body: some View {
        let rows = stride(from: 0, to: labels.count, by: columns).map { start in
            Array(labels[start ..< min(start + columns, labels.count)].enumerated().map { (start + $0.offset, $0.element) })
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 8) {
                    ForEach(pair, id: \.0) { idx, t in chip(t, first: idx == 0) }
                    ForEach(0..<(columns - pair.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func chip(_ t: String, first: Bool) -> some View {
        let tint = first ? accent : coffee
        return HStack(spacing: 5) {
            Text("☕").font(.system(size: 11))
            Text(t).font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .lineLimit(1)
        .foregroundStyle(first ? accent : coffeeInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.15)))
        .overlay(Capsule().stroke(tint.opacity(0.42), lineWidth: 1))
    }
}
