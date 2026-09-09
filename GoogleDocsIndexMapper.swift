import Foundation

struct GoogleDocsIndexMapper {
    func googleRange(for localRange: NSRange, segments: [GoogleDocsTextSegment]) throws -> GoogleDocsTextEdit {
        let start = try googleBoundaryIndex(for: localRange.location, segments: segments)
        let endLocation = localRange.length == 0 ? localRange.location : NSMaxRange(localRange)
        let rawEnd = try googleBoundaryIndex(for: endLocation, segments: segments)
        let end = safeDeleteEndIndex(rawEnd, for: endLocation, segments: segments)
        let tabID = try commonTabID(for: localRange, segments: segments)

        return GoogleDocsTextEdit(
            tabID: tabID,
            googleStartIndex: start,
            googleEndIndex: max(start, end),
            replacementText: ""
        )
    }

    func edit(from originalText: String, to editedText: String, segments: [GoogleDocsTextSegment]) throws -> GoogleDocsTextEdit {
        guard originalText != editedText else {
            throw GoogleDocsServiceError.noChangesToSave
        }

        let original = originalText as NSString
        let edited = editedText as NSString
        let prefixLength = commonPrefixLength(original: original, edited: edited)
        let suffixLength = commonSuffixLength(original: original, edited: edited, prefixLength: prefixLength)
        let originalChangeLength = original.length - prefixLength - suffixLength
        let editedChangeLength = edited.length - prefixLength - suffixLength
        let replacementRange = NSRange(location: prefixLength, length: editedChangeLength)
        let replacementText = edited.substring(with: replacementRange)
        let originalChangeRange = NSRange(location: prefixLength, length: originalChangeLength)
        let isInsertionOnly = originalChangeLength == 0 && !replacementText.isEmpty

        let googleStart = isInsertionOnly
            ? try googleInsertionIndex(for: prefixLength, segments: segments)
            : try googleBoundaryIndex(for: prefixLength, segments: segments)
        let rawGoogleEnd = isInsertionOnly
            ? googleStart
            : try googleBoundaryIndex(for: prefixLength + originalChangeLength, segments: segments)
        let googleEnd = isInsertionOnly
            ? rawGoogleEnd
            : safeDeleteEndIndex(rawGoogleEnd, for: prefixLength + originalChangeLength, segments: segments)
        let tabID = try commonTabID(for: originalChangeRange, segments: segments)

        if googleEnd < googleStart {
            throw GoogleDocsServiceError.unsupportedEditRange
        }

        return GoogleDocsTextEdit(
            tabID: tabID,
            googleStartIndex: googleStart,
            googleEndIndex: googleEnd,
            replacementText: replacementText
        )
    }

    private func commonPrefixLength(original: NSString, edited: NSString) -> Int {
        let limit = min(original.length, edited.length)
        var index = 0

        while index < limit && original.character(at: index) == edited.character(at: index) {
            index += 1
        }

        return index
    }

    private func commonSuffixLength(original: NSString, edited: NSString, prefixLength: Int) -> Int {
        let originalLength = original.length
        let editedLength = edited.length
        var suffixLength = 0

        while suffixLength < originalLength - prefixLength,
              suffixLength < editedLength - prefixLength,
              original.character(at: originalLength - suffixLength - 1) == edited.character(at: editedLength - suffixLength - 1) {
            suffixLength += 1
        }

        return suffixLength
    }

    private func googleBoundaryIndex(for localLocation: Int, segments: [GoogleDocsTextSegment]) throws -> Int {
        for segment in segments {
            if localLocation >= segment.localRange.location && localLocation <= NSMaxRange(segment.localRange) {
                return segment.googleStartIndex + localLocation - segment.localRange.location
            }
        }

        guard let nearbySegment = nearestSegment(forInsertionAt: localLocation, segments: segments) else {
            throw GoogleDocsServiceError.unsupportedEditRange
        }

        return nearbySegment.googleStartIndex
    }

    private func googleInsertionIndex(for localLocation: Int, segments: [GoogleDocsTextSegment]) throws -> Int {
        for segment in segments {
            let localEnd = NSMaxRange(segment.localRange)
            if localLocation >= segment.localRange.location && localLocation <= localEnd {
                let offset = localLocation - segment.localRange.location
                let mappedIndex = segment.googleStartIndex + offset

                if mappedIndex >= segment.googleEndIndex {
                    return max(segment.googleStartIndex, segment.googleEndIndex - 1)
                }

                return mappedIndex
            }
        }

        guard let nearbySegment = nearestSegment(forInsertionAt: localLocation, segments: segments) else {
            throw GoogleDocsServiceError.unsupportedEditRange
        }

        return nearbySegment.googleStartIndex
    }

    private func safeDeleteEndIndex(_ googleEnd: Int, for localEnd: Int, segments: [GoogleDocsTextSegment]) -> Int {
        guard let segment = segments.first(where: { localEnd == NSMaxRange($0.localRange) && googleEnd == $0.googleEndIndex }) else {
            return googleEnd
        }

        return max(segment.googleStartIndex, segment.googleEndIndex - 1)
    }

    private func commonTabID(for localRange: NSRange, segments: [GoogleDocsTextSegment]) throws -> String? {
        if localRange.length == 0 {
            return try tabID(at: localRange.location, segments: segments)
        }

        let touchedSegments = segments.filter { segment in
            NSIntersectionRange(segment.localRange, localRange).length > 0
        }

        guard !touchedSegments.isEmpty else {
            throw GoogleDocsServiceError.unsupportedEditRange
        }

        let tabIDs = Set(touchedSegments.map(\.tabID))
        guard tabIDs.count == 1 else {
            throw GoogleDocsServiceError.unsupportedEditRange
        }

        return touchedSegments[0].tabID
    }

    private func tabID(at localLocation: Int, segments: [GoogleDocsTextSegment]) throws -> String? {
        if let segment = segments.first(where: { localLocation >= $0.localRange.location && localLocation <= NSMaxRange($0.localRange) }) {
            return segment.tabID
        }

        if let nearbySegment = nearestSegment(forInsertionAt: localLocation, segments: segments) {
            return nearbySegment.tabID
        }

        throw GoogleDocsServiceError.unsupportedEditRange
    }

    private func nearestSegment(forInsertionAt localLocation: Int, segments: [GoogleDocsTextSegment]) -> GoogleDocsTextSegment? {
        let sortedSegments = segments.sorted { $0.localRange.location < $1.localRange.location }

        if let nextSegment = sortedSegments.first(where: { localLocation <= $0.localRange.location }) {
            if let previousSegment = sortedSegments.last(where: { NSMaxRange($0.localRange) <= localLocation }),
               previousSegment.tabID != nextSegment.tabID {
                return nil
            }

            return nextSegment
        }

        guard let previousSegment = sortedSegments.last else { return nil }
        return previousSegment
    }
}
