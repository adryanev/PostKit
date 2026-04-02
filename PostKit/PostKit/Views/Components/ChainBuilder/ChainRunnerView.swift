import SwiftUI
import SwiftData

/// View for running chains and viewing results in real-time
struct ChainRunnerView: View {
    @Bindable var viewModel: RequestChainViewModel
    let chain: RequestChain
    
    var body: some View {
        VStack(spacing: 0) {
            // Execution Controls
            executionControls
                .padding()
                .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // Execution Progress
            if viewModel.isExecuting || viewModel.executionState == .completed || viewModel.executionState == .failed(error: "") {
                executionProgress
            }
            
            // Results List
            if !viewModel.stepResults.isEmpty {
                resultsList
            } else {
                emptyState
            }
        }
    }
    
    // MARK: - Execution Controls
    
    @ViewBuilder
    private var executionControls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chain.name)
                    .font(.headline)
                
                Text("\(chain.sortedSteps.count) steps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                if viewModel.isExecuting {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Button(role: .destructive) {
                        viewModel.cancelExecution()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        viewModel.executeChain(chain)
                    } label: {
                        Label("Run Chain", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(chain.sortedSteps.isEmpty)
                    
                    // Run Individual Step
                    if let step = viewModel.selectedStep {
                        Button {
                            viewModel.executeSingleStep(step)
                        } label: {
                            Label("Run Step", systemImage: "play")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
    
    // MARK: - Execution Progress
    
    @ViewBuilder
    private var executionProgress: some View {
        VStack(spacing: 12) {
            switch viewModel.executionState {
            case .idle:
                EmptyView()
                
            case .running(let current, let total):
                VStack(spacing: 8) {
                    ProgressView(value: Double(current), total: Double(total))
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text("Executing step \(current + 1) of \(total)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // Show current step name
                        let steps = chain.sortedSteps
                        if current < steps.count {
                            Text(steps[current].name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                
            case .completed:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    
                    Text("Chain completed successfully")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if let history = viewModel.currentExecutionHistory {
                        Text("\(history.totalDurationMs)ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                
            case .failed(let error):
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    
                    Text("Chain failed: \(error)")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.1))
                
            case .cancelled:
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                    
                    Text("Chain execution cancelled")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }
        }
    }
    
    // MARK: - Results List
    
    @ViewBuilder
    private var resultsList: some View {
        Table(Array(viewModel.stepResults.values.sorted { $0.timestamp < $1.timestamp })) {
            TableColumn("Step") { result in
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.stepName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(result.stepId.uuidString.prefix(8))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            TableColumn("Status") { result in
                HStack(spacing: 4) {
                    if result.success {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Success")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Failed")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }
            
            TableColumn("Code") { result in
                if let code = result.statusCode {
                    Text("\(code)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusCodeColor(code))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusCodeBackground(code))
                        .clipShape(Capsule())
                } else {
                    Text("-")
                        .foregroundStyle(.secondary)
                }
            }
            
            TableColumn("Duration") { result in
                Text("\(result.durationMs)ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            TableColumn("Extracted") { result in
                if result.extractedValues.isEmpty {
                    Text("-")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(result.extractedValues.count) values")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Results Yet", systemImage: "play.circle")
        } description: {
            Text("Run the chain to see results here")
        } actions: {
            Button("Run Chain") {
                viewModel.executeChain(chain)
            }
            .buttonStyle(.borderedProminent)
            .disabled(chain.sortedSteps.isEmpty)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func statusCodeColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        default: return .red
        }
    }
    
    private func statusCodeBackground(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green.opacity(0.2)
        case 300..<400: return .blue.opacity(0.2)
        case 400..<500: return .orange.opacity(0.2)
        default: return .red.opacity(0.2)
        }
    }
}

// MARK: - Chain History Sheet

struct ChainHistorySheet: View {
    let chain: RequestChain
    let viewModel: RequestChainViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if chain.history.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Run the chain to create history entries")
                    )
                } else {
                    ForEach(chain.history.sorted { $0.startedAt > $1.startedAt }) { history in
                        HistoryRow(history: history)
                            .onTapGesture {
                                viewModel.loadHistory(history)
                                dismiss()
                            }
                    }
                    .onDelete { indexes in
                        for index in indexes {
                            let history = chain.history.sorted { $0.startedAt > $1.startedAt }[index]
                            viewModel.modelContext.delete(history)
                        }
                        try? viewModel.modelContext.save()
                    }
                }
            }
            .navigationTitle("Execution History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .destructiveAction) {
                    if !chain.history.isEmpty {
                        Button("Clear All") {
                            viewModel.clearHistory(for: chain)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct HistoryRow: View {
    let history: ChainExecutionHistory
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            switch history.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(history.startedAt, style: .relative)
                    .font(.headline)
                
                Text("\(history.stepResults.count) steps • \(history.totalDurationMs)ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if history.status == .failed, let error = history.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Request Sheet

struct AddRequestToChainSheet: View {
    let requests: [HTTPRequest]
    let onSelect: (HTTPRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var filteredRequests: [HTTPRequest] {
        if searchText.isEmpty {
            return requests
        }
        return requests.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.urlTemplate.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredRequests) { request in
                Button {
                    onSelect(request)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        // Method Badge
                        Text(request.method.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(methodColor(request.method))
                            .frame(width: 50)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.name)
                                .font(.headline)
                            
                            Text(request.urlTemplate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if let collection = request.collection {
                            Text(collection.name)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText)
            .navigationTitle("Add Request to Chain")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private func methodColor(_ method: HTTPMethod) -> Color {
        switch method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return .yellow
        case .delete: return .red
        case .head, .options: return .gray
        }
    }
}

// MARK: - Chain Settings Sheet

struct ChainSettingsSheet: View {
    @Bindable var chain: RequestChain
    @Environment(\.dismiss) private var dismiss
    @State private var description: String
    
    init(chain: RequestChain) {
        self.chain = chain
        self._description = State(initialValue: chain.chainDescription ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    LabeledContent("Name") {
                        TextField("Chain name", text: $chain.name)
                    }
                    
                    LabeledContent("Description") {
                        TextField("Optional description", text: $description)
                    }
                    
                    Toggle("Enabled", isOn: $chain.isEnabled)
                }
                
                Section {
                    Text("Chain ID: \(chain.id.uuidString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Created: \(chain.createdAt.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Steps: \(chain.steps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Details")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Chain Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        chain.chainDescription = description.isEmpty ? nil : description
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - Step Editor Pane

struct StepEditorPane: View {
    @Bindable var step: ChainStep
    let viewModel: RequestChainViewModel
    
    @State private var rules: [ExtractionRule] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Step Name", text: $step.name)
                        .textFieldStyle(.plain)
                        .font(.headline)
                    
                    if let requestID = step.requestID,
                       let request = viewModel.fetchRequest(id: requestID) {
                        HStack(spacing: 8) {
                            Text(request.method.rawValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Text(request.urlTemplate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Step Options
                HStack(spacing: 16) {
                    Toggle("Enabled", isOn: $step.isEnabled)
                        .toggleStyle(.checkbox)
                    
                    Toggle("Continue on Error", isOn: $step.continueOnError)
                        .toggleStyle(.checkbox)
                }
                .font(.caption)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // Extraction Rules
            ScrollView {
                ExtractionEditor(
                    rules: $rules,
                    onAdd: { type in
                        _ = viewModel.addExtractionRule(to: step, type: type)
                        rules = step.extractionRules
                    },
                    onRemove: { rule in
                        viewModel.removeExtractionRule(rule, from: step)
                        rules = step.extractionRules
                    },
                    onUpdate: { rule in
                        viewModel.updateExtractionRule(rule, in: step)
                        rules = step.extractionRules
                    }
                )
                .padding()
            }
        }
        .onAppear {
            rules = step.extractionRules
        }
        .onChange(of: step.extractionRulesData) { _, _ in
            rules = step.extractionRules
        }
    }
}

