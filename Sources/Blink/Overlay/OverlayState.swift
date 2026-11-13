import Combine
import BlinkCore

/// What the toolbar needs to know about the overlay.
@MainActor
final class OverlayState: ObservableObject {
    @Published var isEditing = false
    @Published var isPicking = false
    @Published var shortcutText = ""
    /// The template on the board while one is being tried, and where it is
    /// in the list ("2 of 6").
    @Published var previewName: String?
    @Published var previewPosition = ""
    /// The shelf of templates along the bottom: whether it is open, the
    /// card under the pointer, and the template it has put on the board.
    @Published var isShelfOpen = false
    @Published var shelfPointed: String?
    @Published var shelfShowing: String?
    /// "Using My Day", for a few seconds after a template is kept, with Undo.
    @Published var keptName: String?
    /// Set while something else (the tour) offers its own way to choose.
    @Published var hidesPreviewBar = false
}

/// What the toolbar and launcher can ask the overlay to do.
@MainActor
struct OverlayActions {
    var add: () -> Void = {}
    var templates: () -> Void = {}
    var previewStep: (Int) -> Void = { _ in }
    var keepPreview: () -> Void = {}
    var cancelPreview: () -> Void = {}
    var chooseFromShelf: (BoardTemplate) -> Void = { _ in }
    var closeShelf: () -> Void = {}
    var undoTemplate: () -> Void = {}
    var toggleEditing: () -> Void = {}
    var stopPicking: () -> Void = {}
    var openSettings: () -> Void = {}
}
