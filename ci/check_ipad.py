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
    private var ciChecks = [Bool]()
    private var ciStarted = false
    private var ciContentChecks = [String: Any]()
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard ProcessInfo.processInfo.arguments.contains("--ci-smoke"), !ciStarted else { return }
        ciStarted = true
        waitForDashboard(remaining: 40)
    }
    private func waitForDashboard(remaining: Int) {
        web.evaluateJavaScript("!!(window.ANSWER_CARDS && document.querySelector('#cards .exam-card'))") { [weak self] ready, error in
            guard let self else { return }
            guard error == nil, ready as? Bool == true else {
                guard remaining > 0 else { self.writeSmoke(false, detail: "Dashboard did not become ready: \(String(describing: error))"); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.waitForDashboard(remaining: remaining - 1) }
                return
            }
            self.snapshot("dashboard.png")
            self.auditWebContent()
        }
    }
    private func auditWebContent() {
        let script = #"""
        (() => {
          const failures=[], kinds={concept:0,calculation:0,incomplete:0};
          const normalize=value=>String(value).replace(/\s+/g,' ').trim();
          const expected=value=>{const node=document.createElement('div');node.innerHTML=fmt(value);return normalize(node.textContent);};
          const dashboard=!$('library').hidden && !document.querySelector('.hero')
            && document.querySelector('.library-heading h1')?.textContent==='기출문제'
            && getComputedStyle(document.querySelector('#cards .exam-card')).display==='grid'
            && [...document.styleSheets].some(sheet=>sheet.href?.endsWith('/dashboard.css'));
          let checked=0;
          for (const p of papers) {
            paper=p;queue=[...p.questions];
            for (index=0;index<queue.length;index++) {
              const current=q(), card=window.ANSWER_CARDS[current.id], lesson=window.LESSONS[current.id];
              renderQuestion();
              const answer=$('directAnswerText'), detail=$('lesson');
              const valid=card && card.answer.trim() && normalize(answer.textContent)===expected(card.answer)
                && normalize($('questionText').textContent)===expected(current.prompt)
                && (answer.compareDocumentPosition(detail)&Node.DOCUMENT_POSITION_FOLLOWING)!==0
                && detail.open===(lesson.kind==='calculation') && !$('sourceAnswer').open
                && $('answer').hidden && $('lessonText').children.length>0;
              $('answerToggle').click();
              if (!valid || $('answer').hidden || !$('directAnswerText').textContent.trim()) failures.push(current.id);
              checked++;kinds[lesson.kind]=(kinds[lesson.kind]||0)+1;
            }
          }
          const p=window.PAPERS[0];openPaper(p.id,p.questions[0].no);
          return JSON.stringify({dashboard,checked,answerCards:Object.keys(window.ANSWER_CARDS).length,kinds,failures});
        })()
        """#
        web.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            let audit = (try? JSONSerialization.jsonObject(with: Data((value as? String ?? "{}").utf8))) as? [String: Any] ?? [:]
            self.ciContentChecks = audit
            guard error == nil, audit["dashboard"] as? Bool == true,
                audit["checked"] as? Int == 415, audit["answerCards"] as? Int == 415,
                (audit["failures"] as? [String])?.isEmpty == true else {
                self.writeSmoke(false, detail: error?.localizedDescription ?? "Dashboard / answer binding audit failed: \(audit)")
                return
            }
            let webView = self.web!
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let check = "JSON.stringify({id:q().id, visible:!document.getElementById('study').hidden, prompt:document.getElementById('questionText').innerText, webInkHidden:getComputedStyle(document.querySelector('.canvas-wrap')).display==='none', memoVisible:document.getElementById('typed').getBoundingClientRect().height>0, completeVisible:document.getElementById('complete').getBoundingClientRect().height>0})"
                webView.evaluateJavaScript(check) { value, error in
                    let text = value as? String ?? "{}"
                    let data = text.data(using: .utf8) ?? Data()
                    let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                    let native = NativeChecks.run()
                    let restored = self.checkRestoredFeatures()
                    try? SmoothingChecks.comparisonImage().pngData()?.write(to: URL.documentsDirectory.appendingPathComponent("smoothing.png"))
                    self.canvas.tool = PKEraserTool(.bitmap, width: 48)
                    self.showHover(at: CGPoint(x: 100, y: 120))
                    let hoverOK = !self.hoverTip.isHidden && abs(self.hoverTip.bounds.width - 48 * self.canvas.zoomScale) < 0.1
                        && !self.hoverTip.isUserInteractionEnabled && self.hoverTip.center == CGPoint(x: 100, y: 120)
                    self.canvas.tool = self.pen; self.updateToolStatus()
                    let ok = restored && hoverOK && !self.notebook.isHidden && self.toolButtons.count == 7
                        && result["webInkHidden"] as? Bool == true
                        && result["memoVisible"] as? Bool == true && result["completeVisible"] as? Bool == true
                        && error == nil && self.currentID != nil && self.currentID == result["id"] as? String
                        && result["visible"] as? Bool == true && !(result["prompt"] as? String ?? "").isEmpty
                        && self.canvas.isUserInteractionEnabled && native.hasPrefix("내부 확인 통과")
                    self.snapshot("portrait.png")
                    self.view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        let landscapeOK = self.stack.axis == .horizontal && self.canvasHost.bounds.width > 300 && !self.pinnedQuestion.isHidden
                        self.snapshot("landscape.png")
                        self.checkAnswerScreensAndNavigation { contentOK in
                        let prompt = self.pinnedQuestion.text
                        webView.evaluateJavaScript("if(document.getElementById('answer').hidden)document.getElementById('answerToggle').click(); window.scrollTo(0,document.body.scrollHeight)") { _, _ in
                            let pinnedOK = self.pinnedQuestion.text == prompt && self.pinnedQuestion.window != nil && !self.pinnedQuestion.isHidden
                            self.setAppearance(.dark)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.checkDarkAnswer { darkAnswerOK in
                                self.snapshot("dark.png")
                                self.toggleToolPalette()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    let openOK = self.presentedViewController === self.toolPalette && self.toolPalette != nil
                                    self.snapshot("palette.png", window: true)
                                    self.toggleToolPalette()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        let closeOK = self.presentedViewController == nil
                                        let darkOK = self.view.traitCollection.userInterfaceStyle == .dark && InkAppearance.sameColor((self.pen as? PKInkingTool)?.color, .white)
                                        self.writeSmoke(ok && contentOK && landscapeOK && pinnedOK && openOK && closeOK && darkOK && darkAnswerOK, detail: text + "\n" + native + "\nRestored features: \(restored), answer screens and navigation: \(contentOK), pinned while scrolling: \(pinnedOK), palette open/close: \(openOK)/\(closeOK), dark: \(darkOK), dark answer contrast: \(darkAnswerOK).")
                                    }
                                }
                                }
                            }
                        }
                        }
                    }
                }
            }
        }
    }
    private func checkAnswerScreensAndNavigation(completion: @escaping (Bool) -> Void) {
        web.evaluateJavaScript("openPaper('224241302351',2)") { _, error in
            guard error == nil else { completion(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.web.evaluateJavaScript("document.getElementById('answerToggle').click(); document.getElementById('answer').scrollIntoView(); !document.getElementById('lesson').open && document.getElementById('directAnswerText').textContent.includes('2차압력')") { value, error in
                    let conceptOK = error == nil && value as? Bool == true && self.currentID == "224241302351-2"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.snapshot("concept-answer.png")
                        self.web.evaluateJavaScript("openPaper('224344235204',7)") { _, _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.web.evaluateJavaScript("document.getElementById('answerToggle').click(); document.getElementById('answer').scrollIntoView(); document.getElementById('lesson').open && document.getElementById('directAnswerText').textContent.includes('6,303.03') && document.querySelectorAll('#lessonText .lesson-step').length>1") { value, error in
                                    let calcOK = error == nil && value as? Bool == true && self.currentID == "224344235204-7"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        self.snapshot("calculation-answer.png")
                                        self.web.evaluateJavaScript("document.getElementById('next').click();q().prompt") { nextPrompt, nextError in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                let nextOK = nextError == nil && self.currentID == "224344235204-8"
                                                    && self.pinnedQuestion.text == nextPrompt as? String && self.heading.text?.contains("문제 08") == true
                                                self.web.evaluateJavaScript("document.getElementById('prev').click();q().prompt") { previousPrompt, previousError in
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                        let previousOK = previousError == nil && self.currentID == "224344235204-7"
                                                            && self.pinnedQuestion.text == previousPrompt as? String && self.heading.text?.contains("문제 07") == true
                                                        self.ciContentChecks["concept_screen"] = conceptOK
                                                        self.ciContentChecks["calculation_screen"] = calcOK
                                                        self.ciContentChecks["navigation_bridge"] = nextOK && previousOK
                                                        completion(conceptOK && calcOK && nextOK && previousOK)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private func snapshot(_ name: String, window: Bool = false) {
        let target: UIView = window ? view.window ?? view : view
        let image = UIGraphicsImageRenderer(bounds: target.bounds).image { _ in target.drawHierarchy(in: target.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: URL.documentsDirectory.appendingPathComponent(name))
    }
    private func checkDarkAnswer(completion: @escaping (Bool) -> Void) {
        let script = #"""
        (() => {
          $('answer').scrollIntoView();
          const text=$('directAnswerText'), card=document.querySelector('#answer .direct-answer');
          const luminance=color=>{
            const channels=(color.match(/[\d.]+/g)||[]).slice(0,3).map(n=>{
              const s=Number(n)/255;return s<=0.04045?s/12.92:Math.pow((s+0.055)/1.055,2.4);
            });
            return channels[0]*0.2126+channels[1]*0.7152+channels[2]*0.0722;
          };
          const background=luminance(getComputedStyle(card).backgroundColor), foreground=luminance(getComputedStyle(text).color);
          const contrast=(foreground+0.05)/(background+0.05), bounds=card.getBoundingClientRect();
          return document.documentElement.dataset.nativeTheme==='dark' && !$('answer').hidden
            && background<0.2 && contrast>=4.5 && bounds.top<innerHeight && bounds.bottom>0;
        })()
        """#
        web.evaluateJavaScript(script) { value, error in
            let passed = error == nil && value as? Bool == true
            self.ciContentChecks["dark_answer"] = passed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion(passed) }
        }
    }
    private func checkRestoredFeatures() -> Bool {
        var checks = [Bool]()
        setAppearance(.light); chooseColor(.black, automatic: true)
        checks.append(InkAppearance.sameColor((pen as? PKInkingTool)?.color, .black))
        let source = SmoothingChecks.fixture().strokes[0]
        smoothingSlider.value = 100; smoothingChanged()
        replace(PKDrawing()); beforeStroke = PKDrawing(); writing = true
        canvas.drawing = PKDrawing(strokes:[source]); finishDrawing()
        let corrected = canvas.drawing
        checks.append(corrected.strokes.count == 1 && corrected.strokes[0].path[8].location != source.path[8].location)
        undoInk(); checks.append(canvas.drawing.strokes.isEmpty)
        redoInk(); checks.append(canvas.drawing.strokes.count == 1)
        eraserSlider.value = 73; eraserChanged(); toggleTool(); toggleTool()
        checks.append((canvas.tool as? PKEraserTool)?.width == 73)
        checks.append(UserDefaults.standard.double(forKey:"eraserWidth") == 73 && UserDefaults.standard.double(forKey:"smoothing") == 1)
        setAppearance(.dark); checks.append(InkAppearance.sameColor((pen as? PKInkingTool)?.color, .white) && InkAppearance.sameColor(canvas.drawing.strokes[0].ink.color, .white))
        setAppearance(.light); checks.append(InkAppearance.sameColor(canvas.drawing.strokes[0].ink.color, .black))
        let prompt = pinnedQuestion.text ?? ""; toggleQuestion(); checks.append(!pinnedQuestion.isHidden && !prompt.isEmpty); toggleQuestion()
        // Exercise the same finish/undo path as real drawing, including scaled circles.
        for scale in [CGFloat(0.25), 1, 2] {
            canvas.zoomScale = scale
            let points = (0...160).map { i -> PKStrokePoint in
                let angle = Double(i)/160*3*2*Double.pi
                return PKStrokePoint(location:CGPoint(x:(100+90*cos(angle))/scale,y:(60+55*sin(angle))/scale),timeOffset:Double(i)*0.003,
                    size:CGSize(width:3,height:3),opacity:1,force:0.5,azimuth:0,altitude:.pi/2)
            }
            var base = SmoothingChecks.fixture(); base.transform(using:CGAffineTransform(scaleX:1/scale,y:1/scale))
            let gesture = PKStroke(ink:PKInk(.pen,color:.black),path:PKStrokePath(controlPoints:points,creationDate:Date()))
            replace(base); beforeStroke = base; writing = true; canvas.tool = pen
            canvas.drawing = PKDrawing(strokes:base.strokes + [gesture]); finishDrawing()
            checks.append(canvas.drawing.strokes.count <= base.strokes.count && canvas.drawing.dataRepresentation() != base.dataRepresentation())
            undoInk(); checks.append(canvas.drawing.strokes.count == base.strokes.count)
        }
        canvas.zoomScale = 1; replace(PKDrawing()); canvas.tool = pen
        undoHistory.removeAll(); redoHistory.removeAll(); smoothingSlider.value = 50; smoothingChanged()
        updateToolStatus()
        ciChecks = checks
        return checks.allSatisfy { $0 }
    }
    private func writeSmoke(_ passed: Bool, detail: String) {
        let result: [String: Any] = ["passed":passed, "detail":detail, "feature_checks":ciChecks, "content_checks":ciContentChecks, "scope":"Simulator build and launch; dashboard; all 415 answer bindings and answer-before-explanation order; concept and calculation screens; navigation and native bridge; pinned prompt; eraser size; smoothing strength and undo; theme color components; palette toggle; circle erase at 0.25x/1x/2x, masking and serialization. Physical Pencil and Swift Playground importer NOT tested."]
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
    for name in ('index.html', 'data.js', 'lessons.js', 'answer-cards.js', 'lesson-view.js', 'app.js', 'style.css', 'modern.css', 'dashboard.css'):
        assert (APP / 'Web' / name).is_file(), name
    with (APP / 'Info.plist').open('wb') as file:
        plistlib.dump({'CFBundleIdentifier':BUNDLE, 'CFBundleExecutable':'GasPractice',
            'CFBundleName':'GasPractice', 'CFBundlePackageType':'APPL',
            'CFBundleVersion':'5', 'CFBundleShortVersionString':'0.5',
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
    for image in (container/'Documents').glob('*.png'):
        shutil.copy2(image, OUT/image.name)
    result = json.loads(report.read_text())
    if not result.get('passed'):
        raise RuntimeError(result)
    print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
