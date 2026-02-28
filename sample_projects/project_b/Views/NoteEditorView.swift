import SwiftUI

struct NoteEditorView: View {
    @Binding var title: String
    @Binding var bodyText: String
    var body: some View {
        Form {
            TextField("Title", text: $title)
                .accessibilityIdentifier("noteEditor_title")
            TextEditor(text: $bodyText)
                .accessibilityIdentifier("noteEditor_body")
        }
        .navigationTitle("Edit Note")
        .accessibilityIdentifier("noteEditorScreen")
    }
}
