import Foundation

// MARK: - Versão e checagem de atualização (padrão Overseer/Soprano)

enum AppInfo {
    static let name = "Café no Notch"
    static let version = "0.2.0 beta"
    static let currentTag = "v0.2.0-beta"

    static let repoURL = "https://github.com/bellinivitor/cafe-no-notch"
    static let releasesURL = "https://github.com/bellinivitor/cafe-no-notch/releases"
    static let tagsAPI = "https://api.github.com/repos/bellinivitor/cafe-no-notch/tags"
}

/// Núcleo numérico de uma tag ("v0.1.1-beta" -> [0,1,1]), ignorando 'v' e o
/// sufixo de pré-release ('-beta').
func versionCore(_ tag: String) -> [Int] {
    var s = tag
    if s.hasPrefix("v") { s.removeFirst() }
    if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
    return s.split(separator: ".").map { Int($0) ?? 0 }
}

/// true se a versão `a` for mais nova que `b` (compara número a número).
func isNewerVersion(_ a: String, than b: String) -> Bool {
    let x = versionCore(a), y = versionCore(b)
    for i in 0..<max(x.count, y.count) {
        let xi = i < x.count ? x[i] : 0
        let yi = i < y.count ? y[i] : 0
        if xi != yi { return xi > yi }
    }
    return false
}
