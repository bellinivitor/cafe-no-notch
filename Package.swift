// swift-tools-version: 5.9
import PackageDescription

// NOTA: nesta máquina o SwiftPM/CommandLineTools está com a
// libPackageDescription desencontrada do .swiftmodule, então `swift build`
// falha no link do manifesto. Enquanto isso, use ./build.sh (compila com
// swiftc direto). Este manifesto continua válido para uma toolchain sadia.
let package = Package(
    name: "CafeNoNotch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CafeNoNotch",
            path: "Sources/CafeNoNotch"
        )
    ]
)
