// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "GasPractice",
    platforms: [.iOS("17.5")],
    products: [.iOSApplication(
        name: "가스기사 연습실", targets: ["AppModule"],
        bundleIdentifier: "com.gaspractice.personal.ipad",
        displayVersion: "0.2", bundleVersion: "2",
        appIcon: .placeholder(icon: .pencil), accentColor: .presetColor(.green),
        supportedDeviceFamilies: [.pad],
        supportedInterfaceOrientations: [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
    )],
    targets: [.executableTarget(name: "AppModule", path: ".", resources: [.copy("Resources/Web")])]
)
