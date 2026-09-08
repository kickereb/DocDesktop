import Testing
@testable import DocDesktop

struct GoogleDocsURLParserTests {
    @Test func parsesEditURL() {
        #expect(GoogleDocsURLParser.documentID(from: "https://docs.google.com/document/d/ABC123/edit") == "ABC123")
    }

    @Test func parsesDocumentURLWithoutEditPath() {
        #expect(GoogleDocsURLParser.documentID(from: "https://docs.google.com/document/d/ABC123/") == "ABC123")
    }

    @Test func rejectsSheetsURL() {
        #expect(GoogleDocsURLParser.documentID(from: "https://docs.google.com/spreadsheets/d/ABC123/edit") == nil)
    }

    @Test func rejectsRandomURL() {
        #expect(GoogleDocsURLParser.documentID(from: "https://example.com/document/d/ABC123/edit") == nil)
    }

    @Test func rejectsEmptyString() {
        #expect(GoogleDocsURLParser.documentID(from: "") == nil)
    }
}
