import Testing
@testable import DocDesktop

struct DocumentSyncPolicyTests {
    @Test func unsavedLocalTextIsNeverReplacedByRemote() {
        let policy = DocumentSyncPolicy()

        let decision = policy.decision(hasUnsavedChanges: true, localRevisionID: "local", remoteRevisionID: "remote")

        #expect(decision == .keepLocalUnsaved)
    }

    @Test func remoteChangesLoadWhenLocalTextIsClean() {
        let policy = DocumentSyncPolicy()

        let decision = policy.decision(hasUnsavedChanges: false, localRevisionID: "local", remoteRevisionID: "remote")

        #expect(decision == .loadRemote)
    }

    @Test func sameRevisionDoesNotReload() {
        let policy = DocumentSyncPolicy()

        let decision = policy.decision(hasUnsavedChanges: false, localRevisionID: "same", remoteRevisionID: "same")

        #expect(decision == .noChange)
    }
}
