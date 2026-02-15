import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct OpenAPIImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel = OpenAPIImportViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            StepIndicatorView(
                steps: ImportStep.allCases,
                currentStep: viewModel.currentStep,
                effectiveLastStep: viewModel.effectiveLastStep
            )
            .padding(.vertical, 16)
            
            Divider()
            
            Group {
                switch viewModel.currentStep {
                case .fileSelect:
                    FileSelectStepView(viewModel: viewModel)
                case .target:
                    TargetStepView(viewModel: viewModel)
                case .configure:
                    ConfigureStepView(viewModel: viewModel)
                case .conflicts:
                    ConflictsStepView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(viewModel.currentStep)
            .transition(stepTransition(for: viewModel.navigationDirection))
            
            Divider()
            
            WizardNavigationBar(viewModel: viewModel, dismiss: { dismiss() }, modelContext: modelContext)
        }
        .frame(width: 750, height: 650)
        .onAppear {
            viewModel.loadCollections(context: modelContext)
        }
    }
    
    private func stepTransition(for direction: NavigationDirection) -> AnyTransition {
        switch direction {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

struct StepIndicatorView: View {
    let steps: [ImportStep]
    let currentStep: ImportStep
    let effectiveLastStep: ImportStep
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                if step.rawValue > effectiveLastStep.rawValue {
                    EmptyView()
                } else {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if step.rawValue < currentStep.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(step.rawValue == currentStep.rawValue ? .white : .secondary)
                                }
                            }
                        
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(step.rawValue == currentStep.rawValue ? .semibold : .regular)
                            .foregroundStyle(step.rawValue == currentStep.rawValue ? .primary : .secondary)
                    }
                    
                    if step.rawValue < effectiveLastStep.rawValue {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 40, height: 1)
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }
}

struct FileSelectStepView: View {
    @Bindable var viewModel: OpenAPIImportViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            if let url = viewModel.fileURL {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Text(url.path())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") {
                        selectFile()
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button {
                    selectFile()
                } label: {
                    Label("Select OpenAPI File (JSON, YAML, or YML)", systemImage: "doc.text")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            if viewModel.isLoading {
                ProgressView("Parsing...")
                    .controlSize(.large)
            }
            
            if let error = viewModel.parseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            if let spec = viewModel.spec {
                VStack(alignment: .leading, spacing: 8) {
                    Text(spec.info.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Version: \(spec.info.version)")
                        .foregroundStyle(.secondary)
                    
                    if let description = spec.info.description {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    Label("\(spec.endpoints.count) endpoints", systemImage: "list.bullet")
                        .foregroundStyle(.secondary)
                    
                    if let warning = viewModel.refSkipWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .json,
            UTType(filenameExtension: "yaml")!,
            UTType(filenameExtension: "yml")!
        ]
        
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.parseFile(at: url)
        }
    }
}

struct TargetStepView: View {
    @Bindable var viewModel: OpenAPIImportViewModel
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Import Target")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    viewModel.importMode = .createNew
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text("Create New Collection")
                                .font(.headline)
                            Text("Import as a new collection named \"\(viewModel.spec?.info.title ?? "Imported API")\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .createNew = viewModel.importMode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                if !viewModel.collections.isEmpty {
                    Divider()
                    
                    Text("Or update an existing collection:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    ForEach(viewModel.collections, id: \.id) { collection in
                        Button {
                            viewModel.importMode = .updateExisting(collection)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading) {
                                    Text(collection.name)
                                        .font(.headline)
                                    Text("\(collection.requests.count) requests • Updated \(collection.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if case .updateExisting(let c) = viewModel.importMode, c.id == collection.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            viewModel.loadCollections(context: modelContext)
        }
    }
}

struct ConfigureStepView: View {
    @Bindable var viewModel: OpenAPIImportViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            if let spec = viewModel.spec {
                if !spec.servers.isEmpty {
                    Picker("Server", selection: $viewModel.selectedServer) {
                        ForEach(spec.servers, id: \.url) { server in
                            Text(server.description ?? server.url).tag(Optional(server.url))
                        }
                    }
                    .frame(width: 400)
                }
                
                HStack {
                    Text("Endpoints (\(viewModel.selectedEndpoints.count)/\(spec.endpoints.count) selected)")
                        .font(.headline)
                    Spacer()
                    Button(viewModel.selectedEndpoints.count == spec.endpoints.count ? "Deselect All" : "Select All") {
                        if viewModel.selectedEndpoints.count == spec.endpoints.count {
                            viewModel.deselectAllEndpoints()
                        } else {
                            viewModel.selectAllEndpoints()
                        }
                    }
                }
                
                List {
                    ForEach(spec.endpoints) { endpoint in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { viewModel.selectedEndpoints.contains(endpoint.id) },
                                set: { isSelected in
                                    if isSelected {
                                        viewModel.selectedEndpoints.insert(endpoint.id)
                                    } else {
                                        viewModel.selectedEndpoints.remove(endpoint.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            
                            Text(endpoint.method.rawValue)
                                .fontWeight(.semibold)
                                .foregroundStyle(endpoint.method.color)
                                .frame(width: 60)
                            
                            Text(endpoint.path)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(endpoint.name)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct ConflictsStepView: View {
    @Bindable var viewModel: OpenAPIImportViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            if let diffResult = viewModel.diffResult {
                HStack(spacing: 24) {
                    Label("\(diffResult.newEndpoints.count) new", systemImage: "plus.circle")
                        .foregroundStyle(.green)
                    Label("\(diffResult.changedEndpoints.count) changed", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                    Label("\(diffResult.removedEndpoints.count) removed", systemImage: "minus.circle")
                        .foregroundStyle(.red)
                    Label("\(diffResult.unchangedEndpoints.count) unchanged", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !diffResult.newEndpoints.isEmpty {
                            DisclosureGroup {
                                ForEach(diffResult.newEndpoints) { endpoint in
                                    HStack {
                                        Text(endpoint.method.rawValue)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(endpoint.method.color)
                                            .frame(width: 50)
                                        Text(endpoint.path)
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.vertical, 4)
                                }
                            } label: {
                                Label("New Endpoints (will be added)", systemImage: "plus.circle")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        if !diffResult.changedEndpoints.isEmpty {
                            DisclosureGroup {
                                ForEach(diffResult.changedEndpoints) { change in
                                    ChangedEndpointRow(
                                        change: change,
                                        decision: binding(for: change.id),
                                        requestID: change.existing.requestID
                                    )
                                }
                            } label: {
                                Label("Changed Endpoints (review changes)", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        if !diffResult.removedEndpoints.isEmpty {
                            DisclosureGroup {
                                ForEach(diffResult.removedEndpoints) { snapshot in
                                    RemovedEndpointRow(
                                        snapshot: snapshot,
                                        decision: binding(for: snapshot.id)
                                    )
                                }
                            } label: {
                                Label("Removed Endpoints (no longer in spec)", systemImage: "minus.circle")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Text("No changes to review")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private func binding(for id: String) -> Binding<EndpointDecision?> {
        Binding(
            get: { viewModel.endpointDecisions[id] },
            set: { newValue in
                if let newValue {
                    viewModel.endpointDecisions[id] = newValue
                }
            }
        )
    }
}

struct ChangedEndpointRow: View {
    let change: EndpointChange
    @Binding var decision: EndpointDecision?
    let requestID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(change.existing.method.rawValue)
                    .fontWeight(.semibold)
                    .foregroundStyle(change.existing.method.color)
                    .frame(width: 50)
                Text(change.existing.path)
                Spacer()
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Current:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(change.existing.name)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
                
                VStack(alignment: .leading) {
                    Text("Incoming:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(change.incoming.name)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
            }
            
            Picker("Action", selection: $decision) {
                Text("Keep existing").tag(EndpointDecision.keepExisting(requestID: requestID ?? UUID()) as EndpointDecision?)
                Text("Replace with new").tag(EndpointDecision.replaceExisting(requestID: requestID ?? UUID(), with: change.incomingEndpoint) as EndpointDecision?)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct RemovedEndpointRow: View {
    let snapshot: EndpointSnapshot
    @Binding var decision: EndpointDecision?
    
    var body: some View {
        HStack {
            Text(snapshot.method.rawValue)
                .fontWeight(.semibold)
                .foregroundStyle(snapshot.method.color)
                .frame(width: 50)
            Text(snapshot.path)
            Text(snapshot.name)
                .foregroundStyle(.secondary)
            Spacer()
            
            Picker("", selection: $decision) {
                Text("Keep").tag(EndpointDecision.keepExisting(requestID: snapshot.requestID ?? UUID()) as EndpointDecision?)
                Text("Delete").tag(EndpointDecision.deleteExisting(requestID: snapshot.requestID ?? UUID()) as EndpointDecision?)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.vertical, 4)
    }
}

struct WizardNavigationBar: View {
    @Bindable var viewModel: OpenAPIImportViewModel
    let dismiss: () -> Void
    let modelContext: ModelContext
    
    var body: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            if viewModel.canGoBack {
                Button("Back") {
                    viewModel.goBack()
                }
            }
            
            Button(viewModel.isLastStep ? "Import" : "Next") {
                if viewModel.isLastStep {
                    performImport()
                } else {
                    viewModel.goNext()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canGoNext)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    private func performImport() {
        do {
            try viewModel.performImport(context: modelContext)
            dismiss()
        } catch {
            viewModel.parseError = error.localizedDescription
        }
    }
}

#Preview {
    OpenAPIImportSheet()
}
