import SwiftUI
import AppKit

/// A toolbar for text formatting actions in the compose editor.
struct FormattingToolbar: View {
    /// Reference to the text view for applying formatting
    let textView: NSTextView?

    /// Callback for attaching files
    let onAttach: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            // Bold
            Button {
                if let textView {
                    RichTextEditor.toggleBold(textView: textView)
                }
            } label: {
                Image(systemName: "bold")
            }
            .help("Bold (⌘B)")
            .keyboardShortcut("b", modifiers: .command)

            // Italic
            Button {
                if let textView {
                    RichTextEditor.toggleItalic(textView: textView)
                }
            } label: {
                Image(systemName: "italic")
            }
            .help("Italic (⌘I)")
            .keyboardShortcut("i", modifiers: .command)

            // Underline
            Button {
                if let textView {
                    RichTextEditor.toggleUnderline(textView: textView)
                }
            } label: {
                Image(systemName: "underline")
            }
            .help("Underline (⌘U)")
            .keyboardShortcut("u", modifiers: .command)

            Divider()
                .frame(height: 16)

            // Bullet list
            Button {
                if let textView {
                    RichTextEditor.insertBulletList(textView: textView)
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .help("Bullet List")

            // Numbered list
            Button {
                if let textView {
                    RichTextEditor.insertNumberedList(textView: textView)
                }
            } label: {
                Image(systemName: "list.number")
            }
            .help("Numbered List")

            Divider()
                .frame(height: 16)

            // Attach file
            Button {
                onAttach()
            } label: {
                Image(systemName: "paperclip")
            }
            .help("Attach Files")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

#Preview {
    FormattingToolbar(textView: nil, onAttach: {})
        .frame(width: 400)
}
