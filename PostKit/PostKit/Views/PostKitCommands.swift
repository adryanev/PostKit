import SwiftUI
import SwiftData

struct PostKitCommands: Commands {
    @FocusedValue(\.selectedRequest) var selectedRequest
    @FocusedValue(\.selectedCollection) var selectedCollection
    @FocusedValue(\.sendRequestAction) var sendRequestAction
    @FocusedValue(\.cancelRequestAction) var cancelRequestAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Duplicate Request") {
                duplicateRequest()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(selectedRequest == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Request") {
                selectedRequest?.updatedAt = Date()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(selectedRequest == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Send Request") {
                sendRequestAction?()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(sendRequestAction == nil)

            Button("Cancel Request") {
                cancelRequestAction?()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(cancelRequestAction == nil)
        }
    }

    private func duplicateRequest() {
        guard let source = selectedRequest,
              let collection = source.collection else { return }
        let duplicate = HTTPRequest(name: "\(source.name) (Copy)")
        duplicate.method = source.method
        duplicate.urlTemplate = source.urlTemplate
        duplicate.headersData = source.headersData
        duplicate.queryParamsData = source.queryParamsData
        duplicate.bodyType = source.bodyType
        duplicate.bodyContent = source.bodyContent
        duplicate.authConfigData = source.authConfigData
        duplicate.collection = collection
        duplicate.sortOrder = collection.requests.count
        collection.requests.append(duplicate)
    }
}
