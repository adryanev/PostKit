import SwiftUI
import SwiftData

struct EnvironmentPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<APIEnvironment> { $0.isActive }) private var activeEnvironments: [APIEnvironment]
    @State private var selectedEnvironment: APIEnvironment?
    @State private var showingEnvironmentEditor = false
    
    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $selectedEnvironment) {
                Text("No Environment").tag(nil as APIEnvironment?)
                
                Divider()
                
                ForEach(allEnvironments) { env in
                    HStack {
                        Text(env.name)
                        if env.isActive {
                            Image(systemName: "checkmark")
                        }
                    }
                    .tag(env as APIEnvironment?)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 120, alignment: .leading)
            
            Button {
                showingEnvironmentEditor = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Manage Environments")
        }
        .onAppear {
            selectedEnvironment = activeEnvironments.first
        }
        .onChange(of: selectedEnvironment) { newValue in
            if let env = newValue {
                selectEnvironment(env)
            } else {
                deactivateAllEnvironments()
            }
        }
        .sheet(isPresented: $showingEnvironmentEditor) {
            EnvironmentEditorSheet()
        }
    }
    
    @Query private var allEnvironments: [APIEnvironment]
    
    private func selectEnvironment(_ env: APIEnvironment) {
        deactivateAllEnvironments()
        env.isActive = true
        selectedEnvironment = env
    }
    
    private func deactivateAllEnvironments() {
        for env in allEnvironments {
            env.isActive = false
        }
    }
}

struct EnvironmentEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \APIEnvironment.name) private var environments: [APIEnvironment]
    @State private var selectedEnvironment: APIEnvironment?
    @State private var showingAddEnvironment = false
    @State private var newEnvironmentName = ""
    
    var body: some View {
        Group {
            if environments.isEmpty {
                ContentUnavailableView(
                    "No Environments",
                    systemImage: "globe",
                    description: Text("Add an environment to manage variables")
                )
            } else {
                HSplitView {
                    List(selection: $selectedEnvironment) {
                        ForEach(environments) { env in
                            Text(env.name)
                                .tag(env)
                        }
                    }
                    .frame(minWidth: 150, maxWidth: 200)

                    if let env = selectedEnvironment {
                        EnvironmentVariablesEditor(environment: env)
                    } else {
                        ContentUnavailableView(
                            "Select Environment",
                            systemImage: "globe",
                            description: Text("Choose an environment to edit its variables")
                        )
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
        .navigationTitle("Environments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            
            ToolbarItem {
                Button(action: { showingAddEnvironment = true }) {
                    Label("Add Environment", systemImage: "plus")
                }
            }
            
            ToolbarItem {
                if selectedEnvironment != nil {
                    Button(role: .destructive) {
                        if let env = selectedEnvironment {
                            for variable in env.variables {
                                variable.deleteSecureValue()
                            }
                            modelContext.delete(env)
                            selectedEnvironment = nil
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .alert("New Environment", isPresented: $showingAddEnvironment) {
            TextField("Name", text: $newEnvironmentName)
            Button("Cancel", role: .cancel) {
                newEnvironmentName = ""
            }
            Button("Create") {
                createEnvironment()
            }
        }
    }
    
    private func createEnvironment() {
        guard !newEnvironmentName.isEmpty else { return }
        let env = APIEnvironment(name: newEnvironmentName)
        modelContext.insert(env)
        newEnvironmentName = ""
        selectedEnvironment = env
    }
}

struct EnvironmentVariablesEditor: View {
    @Bindable var environment: APIEnvironment
    @Environment(\.modelContext) private var modelContext
    @State private var selectedVariableID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(environment.name)
                .font(.headline)
            
            Divider()
            
            HStack {
                Text("Variables")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    let variable = Variable(key: "", value: "")
                    variable.environment = environment
                }
                .buttonStyle(.bordered)
            }
            
            if environment.variables.isEmpty {
                ContentUnavailableView(
                    "No Variables",
                    systemImage: "list.bullet",
                    description: Text("Click Add to create a new variable")
                )
            } else {
                Table($environment.variables, selection: $selectedVariableID) {
                    TableColumn("Key") { $variable in
                        TextField("Key", text: $variable.key)
                    }
                    .width(min: 100, max: 200)
                    
                    TableColumn("Value") { $variable in
                        if variable.isSecret {
                            SecureField("Value", text: Binding(
                                get: { variable.secureValue },
                                set: { variable.secureValue = $0 }
                            ))
                        } else {
                            TextField("Value", text: $variable.value)
                        }
                    }
                    
                    TableColumn("Secret") { $variable in
                        Toggle("", isOn: $variable.isSecret)
                            .toggleStyle(.checkbox)
                    }
                    .width(50)
                    
                    TableColumn("Enabled") { $variable in
                        Toggle("", isOn: $variable.isEnabled)
                            .toggleStyle(.checkbox)
                    }
                    .width(60)
                    
                    TableColumn("") { $variable in
                        Button {
                            deleteVariable(variable)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete variable")
                    }
                    .width(30)
                }
                .onDeleteCommand {
                    if let id = selectedVariableID,
                       let variable = environment.variables.first(where: { $0.id == id }) {
                        deleteVariable(variable)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func deleteVariable(_ variable: Variable) {
        variable.deleteSecureValue()
        if let index = environment.variables.firstIndex(where: { $0.id == variable.id }) {
            environment.variables.remove(at: index)
        }
        modelContext.delete(variable)
        selectedVariableID = nil
    }
}

#Preview {
    EnvironmentPicker()
        .modelContainer(for: APIEnvironment.self, inMemory: true)
}
