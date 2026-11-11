import BlickCore
import SwiftUI

/// The controls in the strip along the top of the overlay.
struct ToolbarView: View {
    @ObservedObject var state: OverlayState
    let actions: OverlayActions

    var body: some View {
        HStack(spacing: 8) {
            if state.isPicking {
                Text("Click anything on the page to hide it.  ↑ ↓ widen or narrow the selection.")
                    .foregroundStyle(.secondary)
                Button("Done", action: actions.stopPicking)
            } else {
                Text(state.isEditing
                    ? "Drag a tile to move it, or its edge to resize."
                    : "Press \(state.shortcutText) or esc to close")
                    .foregroundStyle(.secondary)

                Picker("Layout", selection: Binding(get: { state.mode }, set: actions.setMode)) {
                    Text("Flow").tag(LayoutMode.flow)
                    Text("Freeform").tag(LayoutMode.freeform)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Flow arranges tiles in columns for you. Freeform lets you place them anywhere.")

                Button(action: actions.add) {
                    Image(systemName: "plus")
                }
                .help("Add a website, file or widget (⌘N)")

                Button(state.isEditing ? "Done" : "Edit", action: actions.toggleEditing)
                    .help("Move, resize and remove tiles (⌘E)")

                Button(action: actions.openSettings) {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .fixedSize()
    }
}
