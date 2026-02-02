import SwiftUI
import AppKit

/// A rich text editor using NSTextView for email composition.
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isHtml: Bool
    let placeholder: String

    /// Called when text changes
    var onTextChange: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true

        // Configure font
        textView.font = NSFont.systemFont(ofSize: 14)

        // Configure for resizing
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        // Store reference in coordinator
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update text if different
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        // Update placeholder visibility
        context.coordinator.updatePlaceholder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?

        private var placeholderLayer: CATextLayer?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            parent.onTextChange?()
            updatePlaceholder()
        }

        func updatePlaceholder() {
            guard let textView else { return }

            if textView.string.isEmpty && placeholderLayer == nil {
                // Show placeholder
                let layer = CATextLayer()
                layer.string = parent.placeholder
                layer.font = NSFont.systemFont(ofSize: 14)
                layer.fontSize = 14
                layer.foregroundColor = NSColor.placeholderTextColor.cgColor
                layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
                layer.frame = CGRect(x: 5, y: textView.bounds.height - 25, width: textView.bounds.width - 10, height: 20)

                textView.layer?.addSublayer(layer)
                placeholderLayer = layer
            } else if !textView.string.isEmpty {
                // Hide placeholder
                placeholderLayer?.removeFromSuperlayer()
                placeholderLayer = nil
            }
        }
    }

    // MARK: - Formatting

    /// Applies bold formatting to the selection.
    static func toggleBold(textView: NSTextView) {
        applyFontTrait(textView: textView, trait: .boldFontMask)
    }

    /// Applies italic formatting to the selection.
    static func toggleItalic(textView: NSTextView) {
        applyFontTrait(textView: textView, trait: .italicFontMask)
    }

    /// Applies underline formatting to the selection.
    static func toggleUnderline(textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        storage.beginEditing()

        var hasUnderline = false
        storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
            if let style = value as? Int, style != 0 {
                hasUnderline = true
            }
        }

        if hasUnderline {
            storage.removeAttribute(.underlineStyle, range: range)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }

        storage.endEditing()
    }

    /// Inserts a bullet list.
    static func insertBulletList(textView: NSTextView) {
        let range = textView.selectedRange()
        let bullet = "• "

        // Check if previous character is newline with bounds validation
        let isPreviousCharNewline: Bool = {
            guard range.location > 0, range.location <= textView.string.count else { return true }
            let index = textView.string.index(textView.string.startIndex, offsetBy: range.location - 1)
            return textView.string[index] == "\n"
        }()

        if range.location == 0 || isPreviousCharNewline {
            textView.insertText(bullet, replacementRange: range)
        } else {
            textView.insertText("\n" + bullet, replacementRange: range)
        }
    }

    /// Inserts a numbered list.
    static func insertNumberedList(textView: NSTextView) {
        let range = textView.selectedRange()
        let number = "1. "

        // Check if previous character is newline with bounds validation
        let isPreviousCharNewline: Bool = {
            guard range.location > 0, range.location <= textView.string.count else { return true }
            let index = textView.string.index(textView.string.startIndex, offsetBy: range.location - 1)
            return textView.string[index] == "\n"
        }()

        if range.location == 0 || isPreviousCharNewline {
            textView.insertText(number, replacementRange: range)
        } else {
            textView.insertText("\n" + number, replacementRange: range)
        }
    }

    private static func applyFontTrait(textView: NSTextView, trait: NSFontTraitMask) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        storage.beginEditing()

        storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            guard let font = value as? NSFont else { return }

            let fontManager = NSFontManager.shared
            let newFont: NSFont

            if fontManager.traits(of: font).contains(trait) {
                newFont = fontManager.convert(font, toNotHaveTrait: trait)
            } else {
                newFont = fontManager.convert(font, toHaveTrait: trait)
            }

            storage.addAttribute(.font, value: newFont, range: subRange)
        }

        storage.endEditing()
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var text = "Hello, world!"
        @State private var isHtml = true

        var body: some View {
            RichTextEditor(
                text: $text,
                isHtml: $isHtml,
                placeholder: "Write your message here..."
            )
            .frame(width: 500, height: 300)
        }
    }

    return PreviewWrapper()
}
