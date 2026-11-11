import Combine
import GanderCore

/// What the toolbar needs to know about the overlay.
@MainActor
final class OverlayState: ObservableObject {
    @Published var isEditing = false
    @Published var isPicking = false
    @Published var mode: LayoutMode = .flow
    @Published var shortcutText = ""
}

/// What the toolbar and launcher can ask the overlay to do.
@MainActor
struct OverlayActions {
    var add: () -> Void = {}
    var toggleEditing: () -> Void = {}
    var setMode: (LayoutMode) -> Void = { _ in }
    var stopPicking: () -> Void = {}
    var openSettings: () -> Void = {}
}
