import UIKit
import WebKit
import PencilKit
import UniformTypeIdentifiers

@MainActor
final class PracticeController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate,
    PKCanvasViewDelegate, UIPencilInteractionDelegate, UIDocumentPickerDelegate {
    private var web: WKWebView!
    private let canvas = PKCanvasView()
    private let stack = UIStackView(), notebook = UIStackView(), tools = UIStackView()
    private let heading = UILabel(), status = UILabel()
    private var splitConstraint: NSLayoutConstraint?
    private var currentID: String?, beforeStroke: PKDrawing?
    private var undoHistory = [PKDrawing](), redoHistory = [PKDrawing]()
    private var drawings = [String: Data]()
    private var writing = false, replacing = false, storageReady = true
    private var pen: PKTool = PKInkingTool(.pen, color: UIColor(red: 0.12, green: 0.25, blue: 0.22, alpha: 1), width: 3)
    private var tapCount = 0, squeezeCount = 0
    private var lastGesture = "아직 필기하지 않았습니다."
    private let storeURL = URL.documentsDirectory.appendingPathComponent("gas-native-ink-v1.json")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        do {
            if FileManager.default.fileExists(atPath: storeURL.path) {
                drawings = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: storeURL))
                for data in drawings.values { _ = try PKDrawing(data: data) }
            }
        } catch { storageReady = false }
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "practice")
        config.userContentController.addUserScript(WKUserScript(source: Self.bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.isInspectable = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 8; stack.distribution = .fill
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        notebook.axis = .vertical; notebook.spacing = 6
        heading.numberOfLines = 3; heading.font = .preferredFont(forTextStyle: .subheadline)
        heading.text = "회차와 문제를 선택하면 필기장이 열립니다."
        status.font = .preferredFont(forTextStyle: .caption1); status.textColor = .secondaryLabel
        tools.axis = .horizontal; tools.spacing = 6
        let row = UIScrollView(); row.heightAnchor.constraint(equalToConstant: 48).isActive = true
        row.addSubview(tools); tools.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tools.leadingAnchor.constraint(equalTo: row.contentLayoutGuide.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: row.contentLayoutGuide.trailingAnchor),
            tools.topAnchor.constraint(equalTo: row.contentLayoutGuide.topAnchor),
            tools.bottomAnchor.constraint(equalTo: row.contentLayoutGuide.bottomAnchor),
            tools.heightAnchor.constraint(equalTo: row.frameLayoutGuide.heightAnchor)
        ])
        button("펜") { [weak self] in guard let self else { return }; self.canvas.tool = self.pen; self.updateToolStatus() }
        button("지우개") { [weak self] in self?.canvas.tool = PKEraserTool(.bitmap, width: 24); self?.updateToolStatus() }
        button("굵기") { [weak self] in self?.showWidths() }
        button("색") { [weak self] in self?.showColors() }
        button("↶") { [weak self] in self?.undoInk() }
        button("↷") { [weak self] in self?.redoInk() }
        button("전체 지우기") { [weak self] in self?.clearInk() }
        button("필기 백업") { [weak self] in self?.exportInk() }
        button("가져오기") { [weak self] in self?.importInk() }
        button("입력 확인") { [weak self] in self?.showDiagnostics() }
        canvas.delegate = self; canvas.tool = pen; canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.95, alpha: 1)
        canvas.contentSize = CGSize(width: 1600, height: 2400)
        canvas.minimumZoomScale = 0.25; canvas.maximumZoomScale = 2
        canvas.bouncesZoom = true; canvas.isUserInteractionEnabled = false
        let pencil = UIPencilInteraction(); pencil.delegate = self; canvas.addInteraction(pencil)
        notebook.addArrangedSubview(heading); notebook.addArrangedSubview(row)
        notebook.addArrangedSubview(status); notebook.addArrangedSubview(canvas)
        stack.addArrangedSubview(web); stack.addArrangedSubview(notebook)
        if let index = WebResources.indexURL() {
            web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else { report("앱 0.2: 문제 자료를 찾지 못했습니다. 웹사이트에서 학습할 수 있습니다. 기존 프로젝트와 필기는 삭제하지 마세요.") }
        if !storageReady { report("저장된 필기를 읽지 못했습니다. 원본 보호를 위해 새 필기를 중지했습니다. 파일을 삭제하지 말고 오류를 알려주세요.") }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let landscape = view.bounds.width > view.bounds.height
        let axis: NSLayoutConstraint.Axis = landscape ? .horizontal : .vertical
        if splitConstraint == nil || stack.axis != axis {
            splitConstraint?.isActive = false; stack.axis = axis
            splitConstraint = landscape ? web.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.5, constant: -4) : web.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 0.42, constant: -4)
            splitConstraint?.isActive = true
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) {
        let b = UIButton(type: .system); b.configuration = .bordered(); b.setTitle(title, for: .normal)
        b.addAction(UIAction { _ in action() }, for: .touchUpInside); tools.addArrangedSubview(b)
    }
    private func report(_ message: String) { status.text = message; status.textColor = .systemRed }
    private func updateToolStatus() {
        status.textColor = .secondaryLabel
        status.text = canvas.tool is PKEraserTool ? "지우개 · 손가락으로 이동·확대" : "펜 · 손가락으로 이동·확대"
    }
    private func toggleTool() {
        guard currentID != nil, !writing else { return }
        if canvas.tool is PKEraserTool { canvas.tool = pen }
        else { pen = canvas.tool; canvas.tool = PKEraserTool(.bitmap, width: 24) }
        updateToolStatus()
    }
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { tapCount += 1; toggleTool() }
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, currentID != nil, !writing else { return }
        squeezeCount += 1
        menu("필기 도구", options: [
            ("펜 ↔ 지우개", { [weak self] in self?.toggleTool() }),
            ("실행 취소", { [weak self] in self?.undoInk() }),
            ("다시 실행", { [weak self] in self?.redoInk() })
        ])
    }
    private func menu(_ title: String, options: [(String, () -> Void)]) {
        guard !writing else { return }
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        options.forEach { name, action in sheet.addAction(UIAlertAction(title: name, style: .default) { _ in action() }) }
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        sheet.popoverPresentationController?.sourceView = tools
        sheet.popoverPresentationController?.sourceRect = tools.bounds
        guard presentedViewController == nil else { return }
        present(sheet, animated: true)
    }
    private func showWidths() {
        let erasing = canvas.tool is PKEraserTool
        let widths: [CGFloat] = erasing ? [8, 16, 24, 48, 80] : [1.5, 3, 5, 8]
        menu(erasing ? "지우개 크기" : "펜 굵기", options: widths.map { width in
            ("\(width)", { [weak self] in
                guard let self else { return }
                if erasing { self.canvas.tool = PKEraserTool(.bitmap, width: width) }
                else {
                    self.pen = PKInkingTool(.pen, color: (self.pen as? PKInkingTool)?.color ?? .black, width: width)
                    self.canvas.tool = self.pen
                }
            })
        })
    }
    private func showColors() {
        menu("펜 색", options: [("검정", UIColor.black), ("파랑", .systemBlue), ("빨강", .systemRed)].map { title, color in
            (title, { [weak self] in
                guard let self else { return }
                self.pen = PKInkingTool(.pen, color: color, width: (self.pen as? PKInkingTool)?.width ?? 3)
                self.canvas.tool = self.pen; self.updateToolStatus()
            })
        })
    }

    private func save() {
        guard storageReady, let id = currentID else { return }
        drawings[id] = canvas.drawing.dataRepresentation()
        do { try JSONEncoder().encode(drawings).write(to: storeURL, options: .atomic); updateToolStatus() }
        catch { report("필기 저장 실패. 필기 백업으로 파일을 보관하세요. \(error.localizedDescription)") }
    }
    private func replace(_ drawing: PKDrawing) {
        replacing = true; canvas.drawing = drawing; replacing = false
    }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        beforeStroke = canvas.drawing; writing = true; web.isUserInteractionEnabled = false
    }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        // PencilKit commits its last path during this run-loop turn.
        DispatchQueue.main.async { [weak self] in self?.finishDrawing() }
    }
    private func finishDrawing() {
        guard let before = beforeStroke else { return }
        beforeStroke = nil; writing = false; web.isUserInteractionEnabled = true
        if canvas.tool is PKInkingTool, canvas.drawing.strokes.count == before.strokes.count + 1,
           let last = canvas.drawing.strokes.last {
            let region = CircleErase.region(for: last)
            lastGesture = "저장된 획: \(last.path.count)점 · 원 판정: \(region == nil ? "일반 필기" : "지우기")"
            if let region { replace(CircleErase.erase(before, in: region)) }
        } else {
            lastGesture = "획 수 변화: \(before.strokes.count) → \(canvas.drawing.strokes.count)"
        }
        if canvas.drawing.dataRepresentation() != before.dataRepresentation() {
            undoHistory.append(before); if undoHistory.count > 50 { undoHistory.removeFirst() }; redoHistory.removeAll()
        }
        save()
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !replacing, !writing else { return }
        save()
    }
    private func undoInk() {
        guard !writing, let previous = undoHistory.popLast() else { return }
        redoHistory.append(canvas.drawing); replace(previous); save()
    }
    private func redoInk() {
        guard !writing, let next = redoHistory.popLast() else { return }
        undoHistory.append(canvas.drawing); replace(next); save()
    }
    private func clearInk() {
        guard !writing, currentID != nil else { return }
        let alert = UIAlertController(title: "이 문항의 앱 필기를 지울까요?", message: "실행 취소로 복구할 수 있습니다.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "지우기", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.undoHistory.append(self.canvas.drawing); self.redoHistory.removeAll()
            self.replace(PKDrawing()); self.save()
        })
        present(alert, animated: true)
    }
    private func showDiagnostics() {
        let message = "앱 0.2 · iPadOS \(UIDevice.current.systemVersion)\n더블탭 수신: \(tapCount)\n꾹 쥐기 수신: \(squeezeCount)\n\(lastGesture)\n\n\(NativeChecks.run())"
        let alert = UIAlertController(title: "입력 확인", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "닫기", style: .cancel))
        present(alert, animated: true)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any] else { return }
        if body["kind"] as? String == "download", let text = body["text"] as? String {
            share(Data(text.utf8), name: "gas-web-backup.json"); return
        }
        let id = body["id"] as? String
        guard id != currentID, !writing else { return }
        save(); currentID = id; undoHistory.removeAll(); redoHistory.removeAll()
        do {
            if let id, let data = drawings[id] { replace(try PKDrawing(data: data)) }
            else { replace(PKDrawing()) }
        }
        catch { report("이 문항의 필기를 읽지 못했습니다."); canvas.isUserInteractionEnabled = false; return }
        heading.text = body["title"] as? String ?? "회차와 문제를 선택하세요."
        canvas.isUserInteractionEnabled = id != nil && storageReady
        canvas.setContentOffset(.zero, animated: false)
        updateToolStatus()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL { decisionHandler(.allow) }
        else { decisionHandler(.cancel); if ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) } }
    }
    private func share(_ data: Data, name: String) {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
            try data.write(to: url, options: .atomic)
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: 40, width: 1, height: 1)
            present(sheet, animated: true)
        } catch { report("백업 파일을 만들지 못했습니다: \(error.localizedDescription)") }
    }
    private func exportInk() {
        guard !writing else { return }; save()
        do { share(try JSONEncoder().encode(drawings), name: "gas-pencilkit-backup.json") }
        catch { report(error.localizedDescription) }
    }
    private func importInk() {
        guard !writing else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self; present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 100_000_000 else { report("백업 파일이 너무 큽니다."); return }
            let imported = try JSONDecoder().decode([String: Data].self, from: data)
            for ink in imported.values { _ = try PKDrawing(data: ink) }
            let alert = UIAlertController(title: "필기 가져오기", message: "같은 문항의 앱 필기는 백업 내용으로 바뀝니다. 웹 학습 기록은 바뀌지 않습니다.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "취소", style: .cancel))
            alert.addAction(UIAlertAction(title: "가져오기", style: .default) { [weak self] _ in
                guard let self else { return }
                do {
                    let merged = self.drawings.merging(imported) { _, new in new }
                    try JSONEncoder().encode(merged).write(to: self.storeURL, options: .atomic)
                    self.drawings = merged; self.storageReady = true
                    if let id = self.currentID, let ink = merged[id] { self.replace(try PKDrawing(data: ink)) }
                    self.undoHistory.removeAll(); self.redoHistory.removeAll()
                    self.canvas.isUserInteractionEnabled = self.currentID != nil; self.updateToolStatus()
                } catch { self.report("가져오기 실패: \(error.localizedDescription)") }
            })
            present(alert, animated: true)
        } catch { report("앱 필기 백업 형식이 아닙니다. 웹 백업은 목록의 ‘기록 가져오기’를 이용하세요.") }
    }

    private static let bridge = #"""
    (() => {
      const post = value => window.webkit.messageHandlers.practice.postMessage(value);
      let last;
      function sync() {
        const current = document.getElementById('study')?.hidden === false && typeof q === 'function' ? q() : null;
        const id = current?.id ?? null;
        if (last === id) return;
        last = id;
        post({id, title: current ? document.getElementById('qTitle').textContent + '\n' + current.prompt : '회차와 문제를 선택하세요.'});
      }
      addEventListener('load', sync);
      addEventListener('hashchange', () => setTimeout(sync, 0));
      new MutationObserver(sync).observe(document.body, {subtree:true, childList:true, attributes:true, attributeFilter:['hidden']});
      const original = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function() {
        if (this.download && this.href.startsWith('blob:')) {
          fetch(this.href).then(r=>r.text()).then(text=>post({kind:'download',text}));
        } else original.call(this);
      };
      const style = document.createElement('style');
      style.textContent = '.download{display:none}';
      document.head.append(style);
      sync();
    })();
    """#
}
