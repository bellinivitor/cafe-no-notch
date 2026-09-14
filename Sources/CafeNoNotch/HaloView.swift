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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { model.phase != .sleeping }
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

    /// Café com leite — usado quando não há café ativo.
    private var latte: Color { Color(red: 0.80, green: 0.63, blue: 0.45) }

    @ViewBuilder
    private var outline: some View {
        let border = Group {
            if active {
                // borda sutil na cor da fase + sombra/glow verde suave (sem movimento).
                IslandShape(corner: corner, topRounded: model.expanded)
                    .stroke(model.haloColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .shadow(color: model.haloColor.opacity(0.55), radius: 7)
                    .shadow(color: model.haloColor.opacity(0.30), radius: 15)
                    .animation(.easeInOut(duration: 0.6), value: model.haloColor)
            } else {
                // sem café: borda sólida café com leite, sem glow nem movimento.
                IslandShape(corner: corner, topRounded: model.expanded)
                    .stroke(latte, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
        }
        // expandido: sem borda/glow no topo (funde com a câmera).
        if model.expanded {
            border.mask(topFadeMask)
        } else {
            border
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

    var body: some View {
        VStack(spacing: 10) {
            // pager MANUAL: HStack de 2 abas de largura fixa, deslocada por índice
            // e recortada — determinístico, sem vazamento nem descalibragem.
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    agoraPage.frame(width: pageW, height: pagerH, alignment: .topLeading)
                    hojePage.frame(width: pageW, height: pagerH, alignment: .topLeading)
                    sobrePage.frame(width: pageW, height: pagerH, alignment: .topLeading)
                }
                .offset(x: -CGFloat(model.page) * pageW)
                .animation(.easeInOut(duration: 0.3), value: model.page)
            }
            .frame(width: pageW, height: pagerH, alignment: .topLeading)
            .clipped()

            // rodapé fixo: indicador de abas + ações
            HStack(spacing: 12) {
                dots
                Spacer()
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
                FooterButton(title: "Dormir") { model.reset() }
                FooterButton(title: "Sair") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
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

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(model.haloColor)
                        .frame(width: max(6, g.size.width * model.heat))
                        .animation(.easeInOut(duration: 0.5), value: model.heat)
                }
            }
            .frame(height: 6)
        }
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
                Text("nada ainda — bora um? ⌘⇧C")
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

    // ── Aba "Sobre": versão + atualização (padrão Overseer) ──────────────
    private var sobrePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AppInfo.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("v\(AppInfo.version)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            if let t = model.updateTag {
                linkButton("nova versão \(t) — baixar", AppInfo.releasesURL,
                           color: model.haloColor, weight: .medium)
            } else {
                Text("tá na versão mais recente")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.5))
            }

            linkButton("github.com/bellinivitor/cafe-no-notch", AppInfo.repoURL,
                       color: Color(red: 0.86, green: 0.66, blue: 0.46), weight: .regular)

            Text("pra atualizar:  git pull && ./build.sh")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.vertical, 5).padding(.horizontal, 9)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
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
