import AppKit
import GanderCore
import PDFKit
import WebKit

/// A local PDF or HTML file.
final class FileTileContentView: TileContentView {
    private var file: FileContent
    private var viewer: NSView?
    private var loadedModificationDate: Date?

    init(tile: Tile, file: FileContent, settings: AppSettings, context: TileContext) {
        self.file = file
        super.init(tile: tile, settings: settings, context: context)
        loadFile()
    }

    private var fileURL: URL { URL(fileURLWithPath: file.path) }

    override var title: String { file.fileName }

    override func apply(tile: Tile, settings: AppSettings) {
        super.apply(tile: tile, settings: settings)
        guard case .file(let updated) = tile.content, updated != file else { return }
        file = updated
        loadFile()
    }

    /// Picks up edits made to the file since it was last shown.
    override func overlayWillShow() {
        if modificationDate() != loadedModificationDate {
            loadFile()
        }
    }

    override func openExternally() {
        NSWorkspace.shared.open(fileURL)
        dismissOverlay()
    }

    override func addMenuItems(to menu: NSMenu) {
        menu.addItem("Open in Default App") { [weak self] in self?.openExternally() }
        menu.addItem("Show in Finder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting([self.fileURL])
            self.dismissOverlay()
        }
        menu.addItem("Reload") { [weak self] in self?.loadFile() }
    }

    override func layout() {
        super.layout()
        viewer?.frame = bounds
    }

    private func modificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        return attributes?[.modificationDate] as? Date
    }

    private func loadFile() {
        viewer?.removeFromSuperview()
        loadedModificationDate = modificationDate()

        let view: NSView
        if !FileManager.default.fileExists(atPath: file.path) {
            view = MessageView(symbol: "questionmark.folder", text: "\(file.fileName)\nThis file has moved or been deleted.")
        } else {
            switch file.kind {
            case .pdf: view = makePDFView()
            case .html: view = makeHTMLView()
            }
        }
        view.frame = bounds
        addSubview(view)
        viewer = view
    }

    private func makePDFView() -> NSView {
        guard let document = PDFDocument(url: fileURL) else {
            return MessageView(symbol: "doc.badge.ellipsis", text: "\(file.fileName)\nThis PDF could not be opened.")
        }
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor(white: 0.14, alpha: 1)
        return view
    }

    private func makeHTMLView() -> NSView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return view
    }
}
