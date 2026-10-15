"""No signing account required. Actual simulator validation requires macOS/Xcode.
--prepare-only checks packaging locally; it is NOT a successful native test.
"""
import json
import pathlib
import platform
import plistlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification-output'
SRC = ROOT / 'GasPractice.swiftpm'
APP = OUT / 'GasPractice.app'
BUILD = OUT / 'compile-sources'
BUNDLE = 'com.gaspractice.ci'

HARNESS = r'''
    #if CI_SMOKE_TEST
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard ProcessInfo.processInfo.arguments.contains("--ci-smoke") else { return }
        let script = "(() => { const p=window.PAPERS[0]; openPaper(p.id,p.questions[0].no); return window.PAPERS.reduce((n,p)=>n+p.questions.length,0); })()"
        webView.evaluateJavaScript(script) { [weak self] count, error in
            guard let self else { return }
            guard error == nil, (count as? NSNumber)?.intValue == 415 else {
                self.writeSmoke(false, detail: error?.localizedDescription ?? "Question data count failed")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let check = "JSON.stringify({id:q().id, visible:!document.getElementById('study').hidden, prompt:document.getElementById('questionText').innerText, webInkHidden:getComputedStyle(document.querySelector('.canvas-wrap')).display==='none', memoVisible:document.getElementById('typed').getBoundingClientRect().height>0, completeVisible:document.getElementById('complete').getBoundingClientRect().height>0})"
                webView.evaluateJavaScript(check) { value, error in
                    let text = value as? String ?? "{}"
                    let data = text.data(using: .utf8) ?? Data()
                    let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                    let native = NativeChecks.run()
                    self.canvas.tool = PKEraserTool(.bitmap, width: 48)
                    self.showHover(at: CGPoint(x: 100, y: 120))
                    let hoverOK = !self.hoverTip.isHidden && abs(self.hoverTip.bounds.width - 48 * self.canvas.zoomScale) < 0.1
                        && !self.hoverTip.isUserInteractionEnabled && self.hoverTip.center == CGPoint(x: 100, y: 120)
                    self.canvas.tool = self.pen; self.updateToolStatus()
                    let ok = hoverOK && !self.notebook.isHidden && self.toolButtons.count == 7
                        && result["webInkHidden"] as? Bool == true
                        && result["memoVisible"] as? Bool == true && result["completeVisible"] as? Bool == true
                        && error == nil && self.currentID != nil && self.currentID == result["id"] as? String
                        && result["visible"] as? Bool == true && !(result["prompt"] as? String ?? "").isEmpty
                        && self.canvas.isUserInteractionEnabled && native.hasPrefix("내부 확인 통과")
                    let portrait = UIGraphicsImageRenderer(bounds: self.view.bounds).image { _ in
                        self.view.drawHierarchy(in: self.view.bounds, afterScreenUpdates: true)
                    }
                    try? portrait.pngData()?.write(to: URL.documentsDirectory.appendingPathComponent("portrait.png"))
                    self.view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        let landscapeOK = self.stack.axis == .horizontal && self.canvasHost.bounds.width > 300
                        self.writeSmoke(ok && landscapeOK, detail: text + "\n" + native + "\nHover geometry, single notebook, memo/completion, portrait/landscape layout checked. " + (error?.localizedDescription ?? ""))
                    }
                }
            }
        }
    }
    private func writeSmoke(_ passed: Bool, detail: String) {
        let result: [String: Any] = ["passed":passed, "detail":detail, "scope":"Simulator build, resource loading, 415 questions, first question bridge, native geometry/masking and drawing serialization. Physical Pencil and Swift Playground importer NOT tested."]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL.documentsDirectory.appendingPathComponent("ci-smoke.json"), options: .atomic)
        } catch { print("CI_RESULT_WRITE_FAILED: \(error)") }
    }
    #endif
'''

def run(*args):
    command = list(map(str, args))
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    with (OUT / 'build-and-run.log').open('a', encoding='utf-8') as log:
        log.write('$ ' + ' '.join(command) + '\n' + result.stdout + '\n')
    if result.returncode:
        raise RuntimeError(result.stdout)
    return result.stdout

def prepare():
    OUT.mkdir(exist_ok=True)
    BUILD.mkdir(exist_ok=True)
    APP.mkdir(exist_ok=True)
    for source in SRC.glob('*.swift'):
        if source.name != 'Package.swift':
            shutil.copy2(source, BUILD / source.name)
    controller = BUILD / 'PracticeController.swift'
    source = controller.read_text(encoding='utf-8')
    marker = '    func webView(_ webView: WKWebView, decidePolicyFor'
    assert source.count(marker) == 1
    controller.write_text(source.replace(marker, HARNESS + '\n' + marker), encoding='utf-8')
    shutil.copytree(SRC / 'Resources' / 'Web', APP / 'Web', dirs_exist_ok=True)
    for name in ('index.html', 'data.js', 'lessons.js', 'app.js', 'style.css'):
        assert (APP / 'Web' / name).is_file(), name
    with (APP / 'Info.plist').open('wb') as file:
        plistlib.dump({'CFBundleIdentifier':BUNDLE, 'CFBundleExecutable':'GasPractice',
            'CFBundleName':'GasPractice', 'CFBundlePackageType':'APPL',
            'CFBundleVersion':'3', 'CFBundleShortVersionString':'0.3',
            'MinimumOSVersion':'17.5', 'UIDeviceFamily':[2],
            'UILaunchScreen':{}, 'UISupportedInterfaceOrientations':[
                'UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft',
                'UIInterfaceOrientationLandscapeRight']}, file)

def main():
    prepare()
    if '--prepare-only' in sys.argv:
        print('Packaging check only. Native compilation and launch NOT executed.')
        return
    if platform.system() != 'Darwin':
        raise RuntimeError('Native verification requires macOS with Xcode; no success result emitted.')
    sdk = run('xcrun','--sdk','iphonesimulator','--show-sdk-path').strip()
    arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
    run('xcrun','--sdk','iphonesimulator','swiftc','-sdk',sdk,'-target',
        arch+'-apple-ios17.5-simulator','-swift-version','5','-D','CI_SMOKE_TEST',
        '-parse-as-library',*sorted(BUILD.glob('*.swift')),'-o',APP/'GasPractice')
    run('codesign','--force','--sign','-',APP)
    devices = json.loads(run('xcrun','simctl','list','devices','available','-j'))['devices']
    choices = [d for runtime, ds in sorted(devices.items(), reverse=True)
        if 'iOS' in runtime for d in ds if d.get('isAvailable') and 'iPad' in d['name']]
    if not choices:
        raise RuntimeError('No available iPad simulator; verification is blocked.')
    device = choices[0]
    udid = device['udid']
    if device['state'] != 'Booted':
        run('xcrun','simctl','boot',udid)
    run('xcrun','simctl','bootstatus',udid,'-b')
    run('xcrun','simctl','install',udid,APP)
    run('xcrun','simctl','launch','--terminate-running-process',udid,BUNDLE,'--ci-smoke')
    container = pathlib.Path(run('xcrun','simctl','get_app_container',udid,BUNDLE,'data').strip())
    report = container / 'Documents' / 'ci-smoke.json'
    deadline = time.monotonic() + 90
    while not report.exists() and time.monotonic() < deadline:
        time.sleep(1)
    run('xcrun','simctl','io',udid,'screenshot',OUT/'ipad.png')
    if not report.exists():
        raise RuntimeError('App did not produce an execution result within 90 seconds.')
    shutil.copy2(report, OUT/'result.json')
    shutil.copy2(container/'Documents'/'portrait.png', OUT/'portrait.png')
    result = json.loads(report.read_text())
    if not result.get('passed'):
        raise RuntimeError(result)
    print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
