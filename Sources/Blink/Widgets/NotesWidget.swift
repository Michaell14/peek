import BlinkCore
import SwiftUI

/// A scratchpad. The text lives in the tile and is saved with the layout.
@MainActor
struct NotesWidgetView: View {
    let onChange: (NotesConfig) -> Void

    @State private var text: String

    init(config: NotesConfig, onChange: @escaping (NotesConfig) -> Void) {
        self.onChange = onChange
        _text = State(initialValue: config.text)
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: text) { _, updated in
                onChange(NotesConfig(text: updated))
            }
    }
}
