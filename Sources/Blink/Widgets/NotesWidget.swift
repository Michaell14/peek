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
            .font(.system(size: 13.5))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(.horizontal, 11)
            .padding(.vertical, 14)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Jot something down…")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.tertiary)
                        // Lines up with where the editor draws its text.
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: text) { _, updated in
                onChange(NotesConfig(text: updated))
            }
    }
}
