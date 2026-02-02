import SwiftUI

/// A text view that highlights matching substrings.
struct HighlightedText: View {
    let text: String
    let highlight: String
    var highlightColor: Color = .yellow.opacity(0.3)
    var highlightFont: Font = .body.bold()

    var body: some View {
        Text(attributedString)
    }

    private var attributedString: AttributedString {
        var attributed = AttributedString(text)

        guard !highlight.isEmpty else { return attributed }

        let lowercasedText = text.lowercased()
        let lowercasedHighlight = highlight.lowercased()

        var searchStartIndex = lowercasedText.startIndex

        while let range = lowercasedText.range(
            of: lowercasedHighlight,
            range: searchStartIndex..<lowercasedText.endIndex
        ) {
            // Convert String.Index range to AttributedString range
            let startOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
            let endOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound)

            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
            let attrEnd = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)

            let attrRange = attrStart..<attrEnd

            attributed[attrRange].backgroundColor = highlightColor
            attributed[attrRange].font = highlightFont

            searchStartIndex = range.upperBound
        }

        return attributed
    }
}

#Preview("Single Match") {
    HighlightedText(
        text: "This is a test email about quarterly reports",
        highlight: "quarterly"
    )
    .padding()
}

#Preview("Multiple Matches") {
    HighlightedText(
        text: "The report shows the quarterly report results",
        highlight: "report"
    )
    .padding()
}

#Preview("No Match") {
    HighlightedText(
        text: "No matches here",
        highlight: "xyz"
    )
    .padding()
}

#Preview("Empty Highlight") {
    HighlightedText(
        text: "Some text content",
        highlight: ""
    )
    .padding()
}
