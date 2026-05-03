import SwiftUI

/// A `TextField` whose width tracks its content (or the placeholder when
/// empty), bounded by `minWidth`/`maxWidth`. SwiftUI's `TextField` has no
/// built-in equivalent: we drive the layout from a hidden `Text` rendered
/// behind the field, then overlay the actual `TextField` on top.
struct AutoSizingTextField: View {
    let placeholder: String
    @Binding var text: String
    var minWidth: CGFloat = 100
    var maxWidth: CGFloat = 280

    var body: some View {
        ZStack(alignment: .leading) {
            // Hidden sizing text. Padding is tuned to match the rounded-border
            // text field's internal insets so the field grows to exactly fit
            // the typed text plus its border decoration.
            Text(displayedText)
                .font(.body)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .opacity(0)
                .frame(minWidth: minWidth, alignment: .leading)
                .frame(maxWidth: maxWidth, alignment: .leading)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var displayedText: String {
        text.isEmpty ? placeholder : text
    }
}
