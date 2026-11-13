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
}

/// What the toolbar and launcher can ask the overlay to do.
@MainActor
struct OverlayActions {
    var add: () -> Void = {}
    var templates: () -> Void = {}
    var previewStep: (Int) -> Void = { _ in }
    var keepPreview: () -> Void = {}
    var cancelPreview: () -> Void = {}
    var toggleEditing: () -> Void = {}
    var stopPicking: () -> Void = {}
    var openSettings: () -> Void = {}
}
