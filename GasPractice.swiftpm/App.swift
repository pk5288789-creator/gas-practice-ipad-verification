import SwiftUI

@main
struct GasPracticeApp: App {
    var body: some Scene { WindowGroup { PracticeHost().ignoresSafeArea(.container, edges: .bottom) } }
}

struct PracticeHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PracticeController { PracticeController() }
    func updateUIViewController(_ controller: PracticeController, context: Context) {}
}
