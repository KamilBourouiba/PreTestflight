import SwiftUI

struct ShareSheetView: View {
    let note: NoteItem
    var body: some View {
        Text("Share: \(note.title)")
            .accessibilityIdentifier("shareSheet")
    }
}
