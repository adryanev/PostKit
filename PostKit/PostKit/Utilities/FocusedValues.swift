import SwiftUI

// MARK: - Selection Keys

struct SelectedRequestKey: FocusedValueKey {
    typealias Value = HTTPRequest
}

struct SelectedCollectionKey: FocusedValueKey {
    typealias Value = RequestCollection
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

    var selectedCollection: RequestCollection? {
        get { self[SelectedCollectionKey.self] }
        set { self[SelectedCollectionKey.self] = newValue }
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
