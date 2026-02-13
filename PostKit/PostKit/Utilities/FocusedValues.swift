import SwiftUI

// MARK: - Selection Keys

struct SelectedRequestKey: FocusedValueKey {
    typealias Value = HTTPRequest
}

// MARK: - Action Keys

struct SendRequestActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct CancelRequestActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var selectedRequest: HTTPRequest? {
        get { self[SelectedRequestKey.self] }
        set { self[SelectedRequestKey.self] = newValue }
    }

    var sendRequestAction: (() -> Void)? {
        get { self[SendRequestActionKey.self] }
        set { self[SendRequestActionKey.self] = newValue }
    }

    var cancelRequestAction: (() -> Void)? {
        get { self[CancelRequestActionKey.self] }
        set { self[CancelRequestActionKey.self] = newValue }
    }
}
