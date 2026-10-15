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
    private let canvasHost = UIView(), hoverTip = UIView()
    private let pinnedQuestion = UITextView(), questionToggle = UIButton(type: .system)
    private let eraserSlider = UISlider(), smoothingSlider = UISlider()
    private let eraserLabel = UILabel(), smoothingLabel = UILabel()
    private var eraserWidth: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "eraserWidth")).clamped(8...96)
    private var smoothing: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "smoothing")).clamped(0...1)
    private var questionLayout: Bool?
    private weak var toolPalette: UIViewController?
    private var automaticInk = true
    private var isDark: Bool { traitCollection.userInterfaceStyle == .dark }
    private var defaultInk: UIColor { isDark ? .white : .black }
    private var toolButtons = [String: UIButton]()
    private var splitConstraint: NSLayoutConstraint?
    private var currentID: String?, beforeStroke: PKDrawing?
    private var committedDrawing = PKDrawing()
    private var undoHistory = [PKDrawing](), redoHistory = [PKDrawing]()
    private var drawings = [String: Data]()
    private var writing = false, replacing = false, storageReady = true
    private var pen: PKTool = PKInkingTool(.pen, color: UIColor.black, width: 3)
    private var tapCount = 0, squeezeCount = 0
    private var lastGesture = "아직 필기하지 않았습니다."
    private let storeURL = URL.documentsDirectory.appendingPathComponent("gas-native-ink-v1.json")

    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaults.standard.object(forKey: "eraserWidth") == nil { eraserWidth = 24 }
        overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: "appearance")) ?? .unspecified
        view.tintColor = UIColor(red: 0.16, green: 0.34, blue: 0.65, alpha: 1)
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
        notebook.axis = .vertical; notebook.spacing = 8
        notebook.isLayoutMarginsRelativeArrangement = true
        notebook.layoutMargins = UIEdgeInsets(top: 16, left: 12, bottom: 12, right: 12)
        notebook.backgroundColor = .secondarySystemBackground
        notebook.isHidden = true
        heading.numberOfLines = 1; heading.font = .systemFont(ofSize: 17, weight: .semibold)
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
        button("지우개") { [weak self] in guard let self else { return }; self.canvas.tool = PKEraserTool(.bitmap, width: self.eraserWidth); self.updateToolStatus() }
        button("굵기") { [weak self] in self?.showWidths() }
        button("색") { [weak self] in self?.showColors() }
        button("↶") { [weak self] in self?.undoInk() }
        button("↷") { [weak self] in self?.redoInk() }
        button("더 보기") { [weak self] in self?.showMore() }
        pen = PKInkingTool(.pen, color: defaultInk, width: 3)
        canvas.delegate = self; canvas.tool = pen; canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .systemBackground
        canvas.contentSize = CGSize(width: 1600, height: 2400)
        canvas.minimumZoomScale = 0.25; canvas.maximumZoomScale = 2
        canvas.bouncesZoom = true; canvas.isUserInteractionEnabled = false
        let pencil = UIPencilInteraction(); pencil.delegate = self; canvas.addInteraction(pencil)
        let questionHeader = UIStackView(arrangedSubviews: [heading, questionToggle])
        questionHeader.axis = .horizontal; questionHeader.spacing = 8
        questionToggle.setContentHuggingPriority(.required, for: .horizontal)
        questionToggle.addAction(UIAction { [weak self] _ in self?.toggleQuestion() }, for: .touchUpInside)
        pinnedQuestion.isEditable = false; pinnedQuestion.isSelectable = false
        pinnedQuestion.font = .systemFont(ofSize: 14); pinnedQuestion.backgroundColor = .systemBackground
        pinnedQuestion.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        pinnedQuestion.layer.cornerRadius = 12; pinnedQuestion.heightAnchor.constraint(equalToConstant: 110).isActive = true
        pinnedQuestion.accessibilityLabel = "현재 문제"
        notebook.addArrangedSubview(questionHeader); notebook.addArrangedSubview(pinnedQuestion)
        notebook.addArrangedSubview(row)
        notebook.addArrangedSubview(settingRow(label: eraserLabel, slider: eraserSlider, minimum: 8, maximum: 96, value: Float(eraserWidth), name: "지우개 크기", action: #selector(eraserChanged)))
        notebook.addArrangedSubview(settingRow(label: smoothingLabel, slider: smoothingSlider, minimum: 0, maximum: 100, value: Float(smoothing * 100), name: "펜슬 획 보정률", action: #selector(smoothingChanged)))
        canvasHost.layer.cornerRadius = 16; canvasHost.clipsToBounds = true
        canvasHost.layer.borderWidth = 1; canvasHost.layer.borderColor = UIColor.systemGray5.cgColor
        canvasHost.addSubview(canvas); canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: canvasHost.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: canvasHost.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: canvasHost.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: canvasHost.bottomAnchor)
        ])
        hoverTip.isUserInteractionEnabled = false; hoverTip.isHidden = true
        hoverTip.layer.borderWidth = 1.5; canvasHost.addSubview(hoverTip)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(pencilHover(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        hover.cancelsTouchesInView = false; canvas.addGestureRecognizer(hover)
        notebook.addArrangedSubview(status); notebook.addArrangedSubview(canvasHost)
        stack.addArrangedSubview(web); stack.addArrangedSubview(notebook)
        if let index = WebResources.indexURL() {
            web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else { report("앱 0.4: 문제 자료를 찾지 못했습니다. 웹사이트에서 학습할 수 있습니다. 기존 프로젝트와 필기는 삭제하지 마세요.") }
        if !storageReady { report("저장된 필기를 읽지 못했습니다. 원본 보호를 위해 새 필기를 중지했습니다. 파일을 삭제하지 말고 오류를 알려주세요.") }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let landscape = view.bounds.width > view.bounds.height
        let axis: NSLayoutConstraint.Axis = landscape ? .horizontal : .vertical
        if questionLayout != landscape {
            questionLayout = landscape; pinnedQuestion.isHidden = !landscape; updateQuestionToggle()
        }
        if currentID == nil {
            splitConstraint?.isActive = false; splitConstraint = nil
            return
        }
        if splitConstraint == nil || stack.axis != axis {
            splitConstraint?.isActive = false; stack.axis = axis
            splitConstraint = landscape ? web.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.44, constant: -4) : web.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 0.40, constant: -4)
            splitConstraint?.isActive = true
        }
    }

    private func settingRow(label: UILabel, slider: UISlider, minimum: Float, maximum: Float, value: Float, name: String, action: Selector) -> UIStackView {
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 104).isActive = true
        slider.minimumValue = minimum; slider.maximumValue = maximum; slider.value = value
        slider.accessibilityLabel = name; slider.addTarget(self, action: action, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, slider]); row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return row
    }
    private func updateQuestionToggle() {
        questionToggle.setTitle(pinnedQuestion.isHidden ? "문제 펼치기 ⌄" : "문제 접기 ⌃", for: .normal)
        questionToggle.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    }
    private func toggleQuestion() { pinnedQuestion.isHidden.toggle(); updateQuestionToggle() }
    @objc private func eraserChanged() {
        guard !writing else { eraserSlider.value = Float(eraserWidth); return }
        eraserWidth = CGFloat(eraserSlider.value.rounded()); eraserSlider.value = Float(eraserWidth)
        UserDefaults.standard.set(Double(eraserWidth), forKey: "eraserWidth")
        canvas.tool = PKEraserTool(.bitmap, width: eraserWidth); updateToolStatus()
    }
    @objc private func smoothingChanged() {
        guard !writing else { smoothingSlider.value = Float(smoothing * 100); return }
        smoothing = CGFloat(smoothingSlider.value.rounded()) / 100
        UserDefaults.standard.set(Double(smoothing), forKey: "smoothing"); updateToolStatus()
    }
    private func button(_ title: String, action: @escaping () -> Void) {
        let symbols = ["펜":"pencil.tip", "지우개":"eraser", "굵기":"lineweight", "색":"paintpalette", "↶":"arrow.uturn.backward", "↷":"arrow.uturn.forward", "더 보기":"ellipsis"]
        let b = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbols[title] ?? "ellipsis")
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        b.configuration = config; b.accessibilityLabel = title
        b.widthAnchor.constraint(equalToConstant: 46).isActive = true
        toolButtons[title] = b
        b.addAction(UIAction { _ in action() }, for: .touchUpInside); tools.addArrangedSubview(b)
    }
    private func showMore() {
        menu("필기", options: [
            ("필기 백업", { [weak self] in self?.exportInk() }),
            ("백업 가져오기", { [weak self] in self?.importInk() }),
            ("이 문제 필기 지우기", { [weak self] in self?.clearInk() }),
            ("화면·필기 설정", { [weak self] in self?.showToolPalette() }),
            ("입력 확인", { [weak self] in self?.showDiagnostics() })
        ])
    }
    @objc private func pencilHover(_ gesture: UIHoverGestureRecognizer) {
        guard !writing, currentID != nil, canvas.isUserInteractionEnabled,
              gesture.state == .began || gesture.state == .changed else {
            hoverTip.isHidden = true; return
        }
        showHover(at: gesture.location(in: canvasHost))
    }
    private func showHover(at point: CGPoint) {
        let eraser = canvas.tool as? PKEraserTool
        let ink = canvas.tool as? PKInkingTool
        let size = max(eraser == nil ? 4 : 8, (eraser?.width ?? ink?.width ?? 3) * canvas.zoomScale)
        hoverTip.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        hoverTip.center = point; hoverTip.layer.cornerRadius = size / 2
        hoverTip.layer.borderColor = (eraser == nil ? ink?.color ?? .label : .systemBlue).cgColor
        hoverTip.backgroundColor = eraser == nil ? ink?.color : UIColor.systemBlue.withAlphaComponent(0.08)
        hoverTip.isHidden = false
    }
    private func report(_ message: String) { status.text = message; status.textColor = .systemRed }
    private func updateToolStatus() {
        hoverTip.isHidden = true
        eraserLabel.text = "지우개  \(Int(eraserWidth)) pt"
        smoothingLabel.text = "펜슬 보정  \(Int((smoothing * 100).rounded()))%"
        for title in ["펜", "지우개"] {
            let selected = (canvas.tool is PKEraserTool) == (title == "지우개")
            toolButtons[title]?.configuration?.background.backgroundColor = selected ? view.tintColor.withAlphaComponent(0.14) : .clear
            toolButtons[title]?.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        toolButtons["색"]?.tintColor = (pen as? PKInkingTool)?.color
        toolButtons["↶"]?.isEnabled = !undoHistory.isEmpty
        toolButtons["↷"]?.isEnabled = !redoHistory.isEmpty
        status.textColor = .secondaryLabel
        status.text = canvas.tool is PKEraserTool ? "지우개 · 손가락으로 이동·확대" : "펜 · 손가락으로 이동·확대"
    }
    private func toggleTool() {
        guard currentID != nil, !writing else { return }
        if canvas.tool is PKEraserTool { canvas.tool = pen }
        else { pen = canvas.tool; canvas.tool = PKEraserTool(.bitmap, width: eraserWidth) }
        updateToolStatus()
    }
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { tapCount += 1; toggleTool() }
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, currentID != nil, !writing else { return }
        squeezeCount += 1
        toggleToolPalette()
    }
    private func toggleToolPalette() {
        if let palette = toolPalette, presentedViewController === palette {
            palette.dismiss(animated: true); toolPalette = nil
        } else { showToolPalette() }
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
    private func showWidths() { showToolPalette() }
    private func showColors() { showToolPalette() }

    private func chooseColor(_ color: UIColor, automatic: Bool) {
        automaticInk = automatic
        pen = PKInkingTool(.pen, color: automatic ? defaultInk : color, width: (pen as? PKInkingTool)?.width ?? 3)
        canvas.tool = pen; updateToolStatus()
    }
    private func chooseWidth(_ width: CGFloat) {
        pen = PKInkingTool(.pen, color: (pen as? PKInkingTool)?.color ?? defaultInk, width: width)
        canvas.tool = pen; updateToolStatus()
    }
    private func showToolPalette() {
        guard currentID != nil, !writing, presentedViewController == nil else { return }
        let controller = UIViewController(); controller.modalPresentationStyle = .popover
        controller.preferredContentSize = CGSize(width: 350, height: 540)
        controller.view.backgroundColor = .secondarySystemBackground
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        let panel = UIStackView(); panel.axis = .vertical; panel.spacing = 12
        panel.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(panel)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: controller.view.topAnchor), scroll.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            panel.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            panel.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            panel.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        func label(_ title: String) { let l = UILabel(); l.text = title; l.font = .systemFont(ofSize: 13, weight: .semibold); panel.addArrangedSubview(l) }
        func buttons(_ items: [(String, () -> Void)]) {
            let row = UIStackView(); row.spacing = 6; row.distribution = .fillEqually
            for (title, action) in items {
                let b = UIButton(type: .system); var c = UIButton.Configuration.tinted(); c.title = title
                c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in var a = a; a.font = .systemFont(ofSize: 13, weight: .medium); return a }
                b.configuration = c; b.addAction(UIAction { _ in action() }, for: .touchUpInside); row.addArrangedSubview(b)
            }; panel.addArrangedSubview(row)
        }
        label("필기 도구 · 다시 쥐면 닫기")
        buttons([("펜", { [weak self] in guard let self else { return }; self.canvas.tool = self.pen; self.updateToolStatus() }),
                 ("지우개", { [weak self] in guard let self else { return }; self.canvas.tool = PKEraserTool(.bitmap, width: self.eraserWidth); self.updateToolStatus() }),
                 ("닫기", { [weak controller] in controller?.dismiss(animated: true) })])
        label("펜 색상")
        let colors: [(String, UIColor, Bool)] = [(isDark ? "흰색" : "검정", defaultInk, true), ("파랑", .systemBlue, false), ("빨강", .systemRed, false), ("초록", .systemGreen, false)]
        let colorRow = UIStackView(); colorRow.distribution = .fillEqually; colorRow.spacing = 10
        for (name, color, automatic) in colors {
            let b = UIButton(type: .system); var c = UIButton.Configuration.bordered()
            c.image = UIImage(systemName: "circle.fill"); c.title = name; c.imagePlacement = .top; c.imagePadding = 4; c.baseForegroundColor = color
            b.configuration = c; b.accessibilityLabel = name
            b.addAction(UIAction { [weak self] _ in self?.chooseColor(color, automatic: automatic) }, for: .touchUpInside)
            colorRow.addArrangedSubview(b)
        }; panel.addArrangedSubview(colorRow)
        label("펜 굵기")
        buttons([1.5, 3.0, 5.0, 8.0].map { width in ("\(width)", { [weak self] in self?.chooseWidth(CGFloat(width)) }) })
        let eraser = UISlider(), correction = UISlider(), eLabel = UILabel(), cLabel = UILabel()
        let eRow = settingRow(label: eLabel, slider: eraser, minimum: 8, maximum: 96, value: Float(eraserWidth), name: "상세 지우개 크기", action: #selector(paletteSliderUnused))
        eLabel.text = "지우개 \(Int(eraserWidth)) pt"
        eraser.addAction(UIAction { [weak self] _ in
            self?.eraserSlider.value = eraser.value; self?.eraserChanged(); eLabel.text = "지우개 \(Int(eraser.value.rounded())) pt"
        }, for: .valueChanged)
        panel.addArrangedSubview(eRow)
        let cRow = settingRow(label: cLabel, slider: correction, minimum: 0, maximum: 100, value: Float(smoothing*100), name: "상세 펜슬 보정률", action: #selector(paletteSliderUnused))
        cLabel.text = "펜슬 보정 \(Int(smoothing*100))%"
        correction.addAction(UIAction { [weak self] _ in
            self?.smoothingSlider.value = correction.value; self?.smoothingChanged(); cLabel.text = "펜슬 보정 \(Int(correction.value.rounded()))%"
        }, for: .valueChanged); panel.addArrangedSubview(cRow)
        label("획을 마칠 때 보정 · 0%는 원래 획 유지")
        buttons([("실행 취소", { [weak self] in self?.undoInk() }), ("다시 실행", { [weak self] in self?.redoInk() })])
        label("화면 모드")
        buttons([("밝게", { [weak self, weak controller] in self?.setAppearance(.light); controller?.dismiss(animated: true) }),
                 ("어둡게", { [weak self, weak controller] in self?.setAppearance(.dark); controller?.dismiss(animated: true) }),
                 ("시스템", { [weak self, weak controller] in self?.setAppearance(.unspecified); controller?.dismiss(animated: true) })])
        controller.popoverPresentationController?.sourceView = tools
        controller.popoverPresentationController?.sourceRect = tools.bounds
        toolPalette = controller; present(controller, animated: true)
    }
    @objc private func paletteSliderUnused() {}
    private func setAppearance(_ style: UIUserInterfaceStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: "appearance")
        overrideUserInterfaceStyle = style; applyAppearance()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded && previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { applyAppearance() }
    }
    private func applyAppearance() {
        guard web != nil else { return }
        if automaticInk {
            pen = PKInkingTool(.pen, color: defaultInk, width: (pen as? PKInkingTool)?.width ?? 3)
            if canvas.tool is PKInkingTool { canvas.tool = pen }
        }
        replace(InkAppearance.adapt(canvas.drawing, dark: isDark))
        undoHistory = undoHistory.map { InkAppearance.adapt($0, dark: isDark) }
        redoHistory = redoHistory.map { InkAppearance.adapt($0, dark: isDark) }
        web.evaluateJavaScript("document.documentElement.dataset.nativeTheme='\(isDark ? "dark" : "light")'", completionHandler: nil)
        canvasHost.layer.borderColor = UIColor.separator.cgColor
        updateToolStatus()
    }

    private func save() {
        guard storageReady, let id = currentID else { return }
        committedDrawing = canvas.drawing
        drawings[id] = InkAppearance.adapt(canvas.drawing, dark: false).dataRepresentation()
        do { try JSONEncoder().encode(drawings).write(to: storeURL, options: .atomic); updateToolStatus() }
        catch { report("필기 저장 실패. 필기 백업으로 파일을 보관하세요. \(error.localizedDescription)") }
    }
    private func replace(_ drawing: PKDrawing) {
        replacing = true; canvas.drawing = drawing; committedDrawing = drawing; replacing = false
    }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        hoverTip.isHidden = true
        beforeStroke = committedDrawing; writing = true; web.isUserInteractionEnabled = false
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
            let circle = CircleErase.region(for: last, scale: canvas.zoomScale)
            let scribble = circle == nil ? CircleErase.scribbleRegion(for: last, scale: canvas.zoomScale) : nil
            let candidate = circle ?? scribble
            let region = candidate.flatMap { box in before.strokes.contains { $0.renderBounds.intersects(box) } ? box : nil }
            lastGesture = "저장된 획: \(last.path.count)점 · 원 판정: \(region == nil ? "일반 필기" : "지우기")"
            if let region { replace(CircleErase.erase(before, in: region, rectangular: scribble != nil)) }
            else if smoothing > 0 {
                var strokes = canvas.drawing.strokes
                strokes[strokes.count - 1] = PencilSmoothing.apply(last, strength: smoothing)
                replace(PKDrawing(strokes: strokes))
            }
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
        let message = "앱 0.4 · iPadOS \(UIDevice.current.systemVersion)\n더블탭 수신: \(tapCount)\n꾹 쥐기 수신: \(squeezeCount)\n\(lastGesture)\n\n\(NativeChecks.run())"
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
        if body["kind"] as? String == "ready" { applyAppearance(); return }
        let id = body["id"] as? String
        guard id != currentID, !writing else { return }
        save(); currentID = id; undoHistory.removeAll(); redoHistory.removeAll()
        do {
            if let id, let data = drawings[id] { replace(InkAppearance.adapt(try PKDrawing(data: data), dark: isDark)) }
            else { replace(PKDrawing()) }
        }
        catch { report("이 문항의 필기를 읽지 못했습니다."); canvas.isUserInteractionEnabled = false; return }
        let title = (body["title"] as? String ?? "").components(separatedBy: "\n").first ?? ""
        heading.text = "나의 풀이 · " + title
        pinnedQuestion.text = (body["title"] as? String ?? "").components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        pinnedQuestion.setContentOffset(.zero, animated: false)
        notebook.isHidden = id == nil; hoverTip.isHidden = true
        view.setNeedsLayout()
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
                    if let id = self.currentID, let ink = merged[id] { self.replace(InkAppearance.adapt(try PKDrawing(data: ink), dark: self.isDark)) }
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
      style.textContent = `.download,.notebook>.note-title,.notebook>.toolbar,.notebook>#eraserSettings,.notebook>.canvas-wrap{display:none!important}
        body{background:#f6f8fc;color:#263449;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
        .question-card,.notebook{border-color:#e1e7f0;border-radius:16px;box-shadow:none}
        .study-layout{display:block}.question-sidebar{position:static;width:auto}.workspace{min-width:0}
        .question-sidebar .subtle,.question-sidebar .side-link{display:none}
        #questionNumbers{display:flex;flex-wrap:nowrap;overflow-x:auto;gap:6px;margin:8px 0 12px}
        #questionNumbers button{min-width:36px}.question-sidebar>.eyebrow,.question-sidebar>h2,.question-sidebar>p,.question-sidebar>.progress-track,.question-sidebar>a{display:none}
        .question-sidebar .check{display:inline-flex;margin:0 8px 12px}.question-sidebar>button{width:auto;min-height:34px;padding:4px 10px;margin:0 0 12px}
        .notebook{padding-top:14px}.question-card{padding:22px}.question-text{line-height:1.8}
        .primary{background:#2f5795;border-color:#2f5795}.typed-label{font-size:13px}
        .study-dock{position:static;max-height:none;overflow:visible}
        html[data-native-theme=dark]{color-scheme:dark;--bg:#15171b;--paper:#21252c;--ink:#eef1f6;--muted:#a4adbb;--line:#3c424c;--green:#739dff}
        html[data-native-theme=dark] body{background:#15171b;color:#eef1f6}
        html[data-native-theme=dark] :is(.question-card,.notebook,.lesson-step,.answer,.exam-card,textarea,input,button,details,.hero-paper){background:#21252c;color:#eef1f6;border-color:#3c424c}
        html[data-native-theme=dark] :is(.follow-title,.follow-hint,.prose,.eyebrow,.type-tag){color:#d9e5ff}
        html[data-native-theme=dark] :is(.primary,#questionNumbers .active){background:#355d9d;color:white}
        html[data-native-theme=dark] #questionNotices{background:#453b25;color:#ffe3aa}`;
      document.head.append(style);
      post({kind:"ready"});
      sync();
    })();
    """#
}
