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
    @State private var expandedEnvironments: Set<Int> = [0]
    
    var body: some View {
        VStack(spacing: 0) {
            if let spec = viewModel.spec {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !viewModel.isUpdateMode && !spec.servers.isEmpty {
                            environmentsSection(for: spec)
                        } else if !viewModel.isUpdateMode {
                            fallbackEnvironmentView
                        }
                        
                        endpointsSection(for: spec)
                    }
                    .padding()
                }
            }
        }
    }
    
    @ViewBuilder
    private func environmentsSection(for spec: OpenAPISpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Environments")
                    .font(.headline)
                Spacer()
                Text("\(spec.servers.count) will be created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(Array(spec.servers.enumerated()), id: \.offset) { index, server in
                EnvironmentPreviewCard(
                    server: server,
                    securitySchemes: spec.securitySchemes,
                    index: index,
                    isActive: index == 0,
                    isExpanded: expandedEnvironments.contains(index)
                ) {
                    if expandedEnvironments.contains(index) {
                        expandedEnvironments.remove(index)
                    } else {
                        expandedEnvironments.insert(index)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var fallbackEnvironmentView: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Default Environment")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("No servers defined in spec. A single environment will be created.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func endpointsSection(for spec: OpenAPISpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Endpoints")
                        .font(.headline)
                    Text("\(viewModel.selectedEndpoints.count) of \(spec.endpoints.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(viewModel.selectedEndpoints.count == spec.endpoints.count ? "Deselect All" : "Select All") {
                    if viewModel.selectedEndpoints.count == spec.endpoints.count {
                        viewModel.deselectAllEndpoints()
                    } else {
                        viewModel.selectAllEndpoints()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            VStack(spacing: 1) {
                ForEach(spec.endpoints) { endpoint in
                    EndpointRow(
                        endpoint: endpoint,
                        isSelected: viewModel.selectedEndpoints.contains(endpoint.id)
                    ) { isSelected in
                        if isSelected {
                            viewModel.selectedEndpoints.insert(endpoint.id)
                        } else {
                            viewModel.selectedEndpoints.remove(endpoint.id)
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct EnvironmentPreviewCard: View {
    let server: OpenAPIServer
    let securitySchemes: [OpenAPISecurityScheme]
    let index: Int
    let isActive: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    
    private var authTypes: [String] {
        var types: [String] = []
        for scheme in securitySchemes {
            switch scheme.type {
            case .http(let name):
                if name == "bearer" { types.append("Bearer") }
                else if name == "basic" { types.append("Basic") }
            case .apiKey:
                types.append("API Key")
            case .unsupported:
                break
            }
        }
        var seen = Set<String>()
        return types.filter { seen.insert($0).inserted }
    }
    
    private var baseURLDisplay: String {
        var url = server.url
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url.replacingOccurrences(of: "{", with: "{{").replacingOccurrences(of: "}", with: "}}")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton
            if isExpanded {
                expandedContent
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var headerButton: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                statusIndicator
                serverInfo
                Spacer()
                rightSideInfo
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(isActive ? Color.green : Color.secondary.opacity(0.5))
            .frame(width: 8, height: 8)
    }
    
    @ViewBuilder
    private var serverInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(server.description ?? server.url)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if isActive {
                    activeBadge
                }
            }
            
            Text(baseURLDisplay)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var activeBadge: some View {
        Text("ACTIVE")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green)
            .cornerRadius(4)
    }
    
    @ViewBuilder
    private var rightSideInfo: some View {
        HStack(spacing: 8) {
            if !server.variables.isEmpty {
                Label("\(server.variables.count)", systemImage: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            authTypeBadges
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
    }
    
    @ViewBuilder
    private var authTypeBadges: some View {
        if !authTypes.isEmpty {
            HStack(spacing: 4) {
                ForEach(authTypes, id: \.self) { type in
                    authBadge(type)
                }
            }
        }
    }
    
    @ViewBuilder
    private func authBadge(_ type: String) -> some View {
        Text(type)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .cornerRadius(4)
    }
    
    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal, 12)
            
            Text("Variables")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            
            VariableRow(key: "baseUrl", value: baseURLDisplay, isSecret: false)
            
            ForEach(server.variables, id: \.name) { variable in
                VariableRow(key: variable.name, value: variable.defaultValue, isSecret: false)
            }
            
            authVariableRows
        }
        .padding(.bottom, 8)
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    @ViewBuilder
    private var authVariableRows: some View {
        ForEach(authTypes, id: \.self) { type in
            if type == "Bearer" {
                VariableRow(key: "bearerToken", value: "", isSecret: true)
            } else if type == "Basic" {
                VariableRow(key: "basicUsername", value: "", isSecret: false)
                VariableRow(key: "basicPassword", value: "", isSecret: true)
            } else if type == "API Key" {
                VariableRow(key: "apiKeyValue", value: "", isSecret: true)
            }
        }
    }
}

struct VariableRow: View {
    let key: String
    let value: String
    let isSecret: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if isSecret {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
            
            Text("{{\(key)}}")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
            
            if !value.isEmpty {
                Text("=")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("=")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if isSecret {
                    Text("••••••")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

struct EndpointRow: View {
    let endpoint: OpenAPIEndpoint
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { onToggle($0) }
            ))
            .toggleStyle(.checkbox)
            .allowsHitTesting(false)
            
            Text(endpoint.method.rawValue)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(endpoint.method.color)
                .frame(width: 50)
            
            Text(endpoint.path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            
            Spacer()
            
            Text(endpoint.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
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
        VStack(alignment: .leading, spacing: 4) {
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
            
            if snapshot.historyCount > 0 {
                Label("Has \(snapshot.historyCount) history \(snapshot.historyCount == 1 ? "entry" : "entries") — these will be deleted", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 54)
            }
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
