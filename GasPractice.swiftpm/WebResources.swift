import Foundation

// App Playgrounds and SwiftPM may place copied resources in different bundles.
// Do not depend on the generated Bundle.module accessor being present.
enum WebResources {
    static func indexURL() -> URL? {
        let fm = FileManager.default
        let bundles = [Bundle.main, Bundle(for: ResourceAnchor.self)] + Bundle.allBundles
        var roots = bundles.compactMap { $0.resourceURL }
        // SwiftPM resource containers are immediate children of the app bundle.
        for root in roots {
            let children = (try? fm.contentsOfDirectory(at: root,
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            roots.append(contentsOf: children.filter {
                $0.pathExtension == "bundle" || $0.pathExtension == "resources"
            })
        }
        var visited = Set<String>()
        for root in roots where visited.insert(root.path).inserted {
            for folder in ["Web", "Resources/Web", ""] {
                let directory = folder.isEmpty ? root : root.appendingPathComponent(folder)
                let required = ["index.html", "app.js", "data.js", "lessons.js", "style.css"]
                if required.allSatisfy({ fm.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
                    return directory.appendingPathComponent("index.html")
                }
            }
        }
        return nil
    }
    private final class ResourceAnchor: NSObject {}
}
