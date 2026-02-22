import SwiftUI
import SwiftData

struct RequestDetailView: View {
    @Bindable var request: HTTPRequest
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RequestViewModel?

    var body: some View {
        VStack(spacing: 0) {
            URLBar(
                method: $request.method,
                url: $request.urlTemplate,
                isSending: viewModel?.isSending ?? false,
                onSend: { viewModel?.sendRequest(for: request) },
                onCancel: { viewModel?.cancelRequest() }
            )

            Divider()

            HSplitView {
                RequestEditorPane(request: request)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)

                ResponseViewerPane(
                    response: viewModel?.response,
                    error: viewModel?.error,
                    activeTab: activeTabBinding,
                    isLoading: viewModel?.isSending ?? false,
                    request: request,
                    consoleOutput: viewModel?.consoleOutput ?? [],
                    onClearConsole: { viewModel?.consoleOutput.removeAll() }
                )
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusedValue(\.sendRequestAction, { viewModel?.sendRequest(for: request) })
        .focusedValue(\.cancelRequestAction, { viewModel?.cancelRequest() })
        .onAppear {
            if viewModel == nil {
                viewModel = RequestViewModel(modelContext: modelContext)
            }
        }
    }

    /// Provides a two-way binding into the view model's `activeTab`,
    /// falling back to `.body` when the view model has not yet been created.
    private var activeTabBinding: Binding<ResponseTab> {
        Binding(
            get: { viewModel?.activeTab ?? .body },
            set: { viewModel?.activeTab = $0 }
        )
    }
}

#Preview {
    RequestDetailView(request: HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users"))
        .frame(width: 900, height: 600)
        .modelContainer(for: HTTPRequest.self, inMemory: true)
}
