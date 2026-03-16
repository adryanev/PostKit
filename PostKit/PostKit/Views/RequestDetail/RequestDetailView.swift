import SwiftUI
import SwiftData

struct RequestDetailView: View {
    @Bindable var request: HTTPRequest
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RequestViewModel?
    @State private var showCodeGenerator = false
    @State private var showAddToChainSheet = false
    
    @Query(sort: \RequestChain.sortOrder) private var chains: [RequestChain]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                URLBar(
                    method: $request.method,
                    url: $request.urlTemplate,
                    isSending: viewModel?.isSending ?? false,
                    onSend: { viewModel?.sendRequest(for: request) },
                    onCancel: { viewModel?.cancelRequest() }
                )
                .layoutPriority(1)
                
                // Action buttons
                HStack(spacing: 4) {
                    // Add to Chain Button
                    if !chains.isEmpty {
                        Button(action: { showAddToChainSheet = true }) {
                            Image(systemName: "link.badge.plus")
                                .frame(width: 28, height: 28)
                        }
                        .help("Add to Chain")
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: { showCodeGenerator = true }) {
                        Image(systemName: "code")
                            .frame(width: 28, height: 28)
                    }
                    .help("Generate Code")
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 12)
            }

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
        .sheet(isPresented: $showCodeGenerator) {
            CodeGeneratorView(request: request)
        }
        .sheet(isPresented: $showAddToChainSheet) {
            AddRequestToChainPicker(request: request, chains: chains)
        }
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

// MARK: - Add Request to Chain Picker

struct AddRequestToChainPicker: View {
    let request: HTTPRequest
    let chains: [RequestChain]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChain: RequestChain?
    @State private var stepName = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Select Chain", selection: $selectedChain) {
                        Text("Select a chain...").tag(nil as RequestChain?)
                        ForEach(chains) { chain in
                            Text(chain.name).tag(chain as RequestChain?)
                        }
                    }
                } header: {
                    Text("Chain")
                } footer: {
                    Text("Choose which chain to add this request to")
                }
                
                Section {
                    TextField("Optional step name", text: $stepName)
                } header: {
                    Text("Step Name")
                } footer: {
                    Text("Leave empty to use the request name")
                }
                
                if let chain = selectedChain {
                    Section("Chain Info") {
                        LabeledContent("Steps", value: "\(chain.steps.count)")
                        LabeledContent("Status", value: chain.isEnabled ? "Enabled" : "Disabled")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add to Chain")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRequestToChain()
                    }
                    .disabled(selectedChain == nil)
                }
            }
        }
        .frame(width: 400, height: 350)
    }
    
    private func addRequestToChain() {
        guard let chain = selectedChain else { return }
        
        let chainViewModel = RequestChainViewModel(modelContext: modelContext)
        _ = chainViewModel.addStep(to: chain, request: request, name: stepName.isEmpty ? nil : stepName)
        
        dismiss()
    }
}

#Preview {
    RequestDetailView(request: HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users"))
        .frame(width: 900, height: 600)
        .modelContainer(for: HTTPRequest.self, inMemory: true)
}
