import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Visual flow builder for request chains
struct ChainBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel: RequestChainViewModel
    @State private var chain: RequestChain
    @State private var showingAddRequestSheet = false
    @State private var showingChainSettings = false
    @State private var showingExecutionHistory = false
    
    @Query private var allRequests: [HTTPRequest]
    
    init(chain: RequestChain, modelContext: ModelContext) {
        self._chain = State(initialValue: chain)
        self._viewModel = State(initialValue: RequestChainViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
        }
        .navigationTitle(chain.name)
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingAddRequestSheet) {
            AddRequestToChainSheet(
                requests: allRequests,
                onSelect: { request in
                    viewModel.addStep(to: chain, request: request)
                }
            )
        }
        .sheet(isPresented: $showingChainSettings) {
            ChainSettingsSheet(chain: chain)
        }
        .sheet(isPresented: $showingExecutionHistory) {
            ChainHistorySheet(chain: chain, viewModel: viewModel)
        }
        .onAppear {
            viewModel.selectedChain = chain
        }
    }
    
    // MARK: - Sidebar
    
    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Steps List
            List(selection: $viewModel.selectedStep) {
                Section("Steps (\(chain.sortedSteps.count))") {
                    ForEach(chain.sortedSteps) { step in
                        ChainStepRowView(
                            step: step,
                            result: viewModel.stepResults[step.id],
                            request: viewModel.fetchRequest(id: step.requestID ?? UUID())
                        )
                        .tag(step)
                        .onDrag {
                            viewModel.draggedStep = step
                            return NSItemProvider(object: step.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: StepDropDelegate(
                            step: step,
                            viewModel: viewModel
                        ))
                    }
                    .onDelete(perform: deleteSteps)
                    .onMove(perform: moveSteps)
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // Add Step Button
            HStack {
                Button(action: { showingAddRequestSheet = true }) {
                    Label("Add Request", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Visual Flow Canvas
            ScrollView {
                FlowCanvasView(
                    chain: chain,
                    viewModel: viewModel,
                    onStepTap: { step in
                        viewModel.selectedStep = step
                    }
                )
                .padding()
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Selected Step Editor
            if let selectedStep = viewModel.selectedStep {
                StepEditorPane(step: selectedStep, viewModel: viewModel)
                    .frame(maxHeight: 300)
            } else {
                emptySelectionPlaceholder
            }
        }
    }
    
    @ViewBuilder
    private var emptySelectionPlaceholder: some View {
        ContentUnavailableView(
            "Select a Step",
            systemImage: "hand.tap",
            description: Text("Select a step from the list to edit its extraction rules")
        )
        .frame(maxHeight: 200)
    }
    
    // MARK: - Toolbar
    
    @ViewBuilder
    private var toolbarContent: some View {
        // Run Controls
        if viewModel.isExecuting {
            Button(role: .destructive) {
                viewModel.cancelExecution()
            } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
        } else {
            Button {
                viewModel.executeChain(chain)
            } label: {
                Label("Run Chain", systemImage: "play.fill")
            }
            .disabled(chain.steps.isEmpty)
        }
        
        Button {
            showingExecutionHistory = true
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
        }

        Button {
            showingChainSettings = true
        } label: {
            Label("Settings", systemImage: "slider.horizontal.3")
        }

        Menu {
                Button {
                    let copy = viewModel.duplicateChain(chain)
                    chain = copy
                } label: {
                    Label("Duplicate Chain", systemImage: "doc.on.doc")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    viewModel.deleteChain(chain)
                    dismiss()
                } label: {
                    Label("Delete Chain", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
    }

    // MARK: - Actions
    
    private func deleteSteps(at offsets: IndexSet) {
        let steps = chain.sortedSteps
        for index in offsets {
            viewModel.removeStep(steps[index])
        }
    }
    
    private func moveSteps(from source: IndexSet, to destination: Int) {
        let steps = chain.sortedSteps
        for index in source {
            let step = steps[index]
            viewModel.moveStep(step, to: destination)
        }
    }
}

// MARK: - Flow Canvas View

/// Visual canvas showing the chain flow with connected nodes
struct FlowCanvasView: View {
    let chain: RequestChain
    let viewModel: RequestChainViewModel
    let onStepTap: (ChainStep) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            ForEach(Array(chain.sortedSteps.enumerated()), id: \.element.id) { index, step in
                ChainStepNodeView(
                    step: step,
                    index: index,
                    result: viewModel.stepResults[step.id],
                    isSelected: viewModel.selectedStep?.id == step.id,
                    request: viewModel.fetchRequest(id: step.requestID ?? UUID())
                )
                .onTapGesture {
                    onStepTap(step)
                }
                
                // Connection Arrow
                if index < chain.sortedSteps.count - 1 {
                    connectionArrow
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    @ViewBuilder
    private var connectionArrow: some View {
        VStack(spacing: 4) {
            // Show extracted values flowing to next step
            if let step = chain.sortedSteps.first,
               let result = viewModel.stepResults[step.id],
               !result.extractedValues.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(result.extractedValues.keys.sorted()), id: \.self) { key in
                        if let value = result.extractedValues[key] {
                            HStack(spacing: 2) {
                                Text("{{\(key)}}")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.blue)
                                Text("=")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(truncated(value, maxLength: 20))
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            
            Image(systemName: "arrow.down")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
    
    private func truncated(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        return String(string.prefix(maxLength)) + "..."
    }
}

// MARK: - Step Drop Delegate

struct StepDropDelegate: DropDelegate {
    let step: ChainStep
    let viewModel: RequestChainViewModel
    
    func performDrop(info: DropInfo) -> Bool {
        viewModel.dropTargetStep = nil
        guard let draggedStep = viewModel.draggedStep else { return false }
        
        if draggedStep.id != step.id {
            viewModel.moveStep(draggedStep, to: step.stepOrder)
        }
        
        viewModel.draggedStep = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        viewModel.dropTargetStep = step
    }
    
    func dropExited(info: DropInfo) {
        if viewModel.dropTargetStep?.id == step.id {
            viewModel.dropTargetStep = nil
        }
    }
}

// MARK: - Chain Step Row View

struct ChainStepRowView: View {
    let step: ChainStep
    let result: ChainStepResult?
    let request: HTTPRequest?
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            statusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name.isEmpty ? (request?.name ?? "Unknown Request") : step.name)
                    .font(.headline)
                    .lineLimit(1)
                
                if let request = request {
                    HStack(spacing: 4) {
                        Text(request.method.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(methodColor)
                        
                        Text(request.urlTemplate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Result Badge
            if let result = result {
                resultBadge(result)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        if let result = result {
            if result.success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func resultBadge(_ result: ChainStepResult) -> some View {
        if let statusCode = result.statusCode {
            Text("\(statusCode)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(statusCodeColor(statusCode))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusCodeBackground(statusCode))
                .clipShape(Capsule())
        }
    }
    
    private var methodColor: Color {
        guard let request = request else { return .secondary }
        switch request.method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return .yellow
        case .delete: return .red
        case .head, .options: return .gray
        }
    }

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

// MARK: - Chain Step Node View

struct ChainStepNodeView: View {
    let step: ChainStep
    let index: Int
    let result: ChainStepResult?
    let isSelected: Bool
    let request: HTTPRequest?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Circle()
                    .fill(stepNumberColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(stepName)
                        .font(.headline)
                    
                    if let request = request {
                        HStack(spacing: 4) {
                            Text(request.method.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(methodColor)
                            
                            Text(request.urlTemplate)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Extraction count
                if !step.extractionRules.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("\(step.extractionRules.count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            
            // Extracted Values
            if let result = result, !result.extractedValues.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extracted Values")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(result.extractedValues.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        HStack {
                            Text("{{\(key)}}")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                            
                            Text("=")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text(value)
                                .font(.caption)
                                .foregroundStyle(.green)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button {
                                copyToClipboard(value)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // Error Message
            if let result = result, let error = result.errorMessage {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(nodeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    private var stepName: String {
        step.name.isEmpty ? (request?.name ?? "Unknown Request") : step.name
    }
    
    private var stepNumberColor: Color {
        if let result = result {
            return result.success ? .green : .red
        }
        return .blue
    }
    
    private var methodColor: Color {
        guard let request = request else { return .secondary }
        switch request.method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return .yellow
        case .delete: return .red
        case .head, .options: return .gray
        }
    }

    private var nodeBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        return Color(.windowBackgroundColor)
    }
    
    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Helper

func copyToClipboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

