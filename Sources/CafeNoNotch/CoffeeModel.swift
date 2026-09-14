import Foundation
import SwiftUI

/// Estado térmico do café ao longo do tempo.
/// Modelo simples e legível — o refino de curva/temperatura vem depois.
final class CoffeeModel: ObservableObject {

    /// Minutos até o café ser considerado "frio" de vez.
    static let coolMinutes: Double = 30
    /// Faixa de temperatura simulada (°C) só para exibição.
    static let hotC: Double = 68
    static let coldC: Double = 24

    /// Momento em que o café foi feito. `nil` = dormindo (nenhum café ativo).
    @Published private(set) var brewedAt: Date?
    /// Atualizado a cada tick do timer só para forçar o redesenho.
    @Published private(set) var now: Date = Date()
    /// Painel do dia aberto (ilha expandida)?
    @Published var expanded: Bool = false
    /// Aba ativa no painel (0 = Agora, 1 = Cafés hoje, 2 = Sobre).
    @Published var page: Int = 0
    /// Tag mais recente no GitHub, se for mais nova que a instalada.
    @Published var updateTag: String?

    /// Atalho global configurável (padrão: nenhum). keyCode/mods em Carbon.
    @Published var hotKeyCode: UInt32 = UInt32(max(0, UserDefaults.standard.integer(forKey: "hotKeyCode")))
    @Published var hotKeyMods: UInt32 = UInt32(max(0, UserDefaults.standard.integer(forKey: "hotKeyMods")))
    @Published var hotKeyChar: String = UserDefaults.standard.string(forKey: "hotKeyChar") ?? ""
    /// Horários dos cafés de hoje (mais recente primeiro).
    @Published private(set) var history: [Date] = []

    private var timer: Timer?

    enum Phase {
        case sleeping, hot, warm, cooling, cold

        var label: String {
            switch self {
            case .sleeping: return "Cadê o café?"
            case .hot:      return "Quentinho"
            case .warm:     return "Ainda salva"
            case .cooling:  return "Tá esfriando"
            case .cold:     return "Frio 💀"
            }
        }
    }

    /// Minutos decorridos desde o café (0 se dormindo).
    var elapsedMinutes: Double {
        guard let brewedAt else { return 0 }
        return now.timeIntervalSince(brewedAt) / 60
    }

    /// Fração de calor restante, de 1 (recém-feito) a 0 (frio).
    var heat: Double {
        guard brewedAt != nil else { return 0 }
        return max(0, 1 - elapsedMinutes / Self.coolMinutes)
    }

    /// Temperatura simulada em °C.
    var temperatureC: Int {
        Int((Self.coldC + (Self.hotC - Self.coldC) * heat).rounded())
    }

    var phase: Phase {
        guard brewedAt != nil else { return .sleeping }
        switch elapsedMinutes {
        case ..<10:  return .hot
        case ..<20:  return .warm
        case ..<28:  return .cooling
        default:     return .cold
        }
    }

    /// Cor do halo: verde (quente) → âmbar → vermelho (frio), interpolando o matiz.
    var haloColor: Color {
        let hue = max(5, 145 - (elapsedMinutes / Self.coolMinutes) * 140) / 360
        let sat: Double
        let bri: Double
        switch phase {
        case .hot:     sat = 0.62; bri = 0.80
        case .warm:    sat = 0.70; bri = 0.82
        case .cooling: sat = 0.92; bri = 0.90
        case .cold:    sat = 0.78; bri = 0.85
        case .sleeping:sat = 0.10; bri = 0.55
        }
        return Color(hue: hue, saturation: sat, brightness: bri)
    }

    /// Verde (ou cor da fase) vívido, para o brilho que percorre o halo.
    var haloBright: Color {
        let hue = max(5, 145 - (elapsedMinutes / Self.coolMinutes) * 140) / 360
        return Color(hue: hue, saturation: 1.0, brightness: 1.0)
    }

    var subtitle: String {
        switch phase {
        case .sleeping: return "bora fazer um?"
        case .hot:      return "no ponto, aproveita"
        case .warm:     return "ainda rende uns goles"
        case .cooling:  return "corre pro último gole"
        case .cold:     return "faz outro, vai"
        }
    }

    // MARK: - Ações

    func brew() {
        let d = Date()
        brewedAt = d
        now = d
        history.insert(d, at: 0)
        if history.count > 12 { history.removeLast() }
    }

    func reset() {
        brewedAt = nil
    }

    func toggleExpanded() { expanded.toggle() }
    func setExpanded(_ v: Bool) {
        if expanded != v { expanded = v }
        if !v { page = 0 }   // volta pra 1ª aba ao recolher
    }
    func setPage(_ p: Int) { let c = max(0, min(2, p)); if page != c { page = c } }

    /// Rótulo do atalho atual ("não definido" quando vazio).
    var hotKeyLabel: String {
        hotKeyCode == 0 ? "nenhum" : modifierGlyphs(hotKeyMods) + hotKeyChar
    }

    func updateHotKey(keyCode: UInt32, mods: UInt32, char: String) {
        hotKeyCode = keyCode; hotKeyMods = mods; hotKeyChar = char
        let d = UserDefaults.standard
        d.set(Int(keyCode), forKey: "hotKeyCode")
        d.set(Int(mods), forKey: "hotKeyMods")
        d.set(char, forKey: "hotKeyChar")
    }

    /// Consulta as tags do repo e sinaliza se a mais recente for mais nova que a
    /// versão instalada (mesmo padrão do Overseer).
    func checkForUpdate() {
        guard let url = URL(string: AppInfo.tagsAPI) else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("CafeNoNotch-app", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let names = arr.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
            let newest = names.max { isNewerVersion($1, than: $0) }
            DispatchQueue.main.async {
                if let newest, isNewerVersion(newest, than: AppInfo.currentTag) {
                    self?.updateTag = newest
                } else {
                    self?.updateTag = nil
                }
            }
        }.resume()
    }

    /// Horários de hoje formatados "HH:mm" (mais recente primeiro).
    func todayLabels() -> [String] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return history.filter { cal.isDateInToday($0) }.map { fmt.string(from: $0) }
    }

    func startTicking() {
        checkForUpdate()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
