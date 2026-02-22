import SwiftUI
import SwiftData

struct CollectionDetailView: View {
    @Bindable var collection: RequestCollection
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: DetailTab = .environments
    
    enum DetailTab: String, CaseIterable {
        case environments = "Environments"
        case settings = "Settings"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
                Text(collection.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            
            Divider()
            
            Picker("Tab", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            switch selectedTab {
            case .environments:
                CollectionEnvironmentsView(collection: collection)
            case .settings:
                CollectionSettingsView(collection: collection)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct CollectionEnvironmentsView: View {
    @Bindable var collection: RequestCollection
    @Environment(\.modelContext) private var modelContext
    @State private var selectedEnvironment: APIEnvironment?
    @State private var showingAddEnvironment = false
    @State private var newEnvironmentName = ""
    
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Environments")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingAddEnvironment = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.top)
                
                List(selection: $selectedEnvironment) {
                    ForEach(collection.environments.sorted(by: { $0.name < $1.name })) { env in
                        HStack {
                            Text(env.name)
                            Spacer()
                            if env.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .tag(env)
                    }
                }
            }
            .frame(minWidth: 180, maxWidth: 250)
            
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
        env.collection = collection
        modelContext.insert(env)
        newEnvironmentName = ""
        selectedEnvironment = env
    }
}

struct CollectionSettingsView: View {
    @Bindable var collection: RequestCollection
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Collection Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Name:") {
                            TextField("Name", text: $collection.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Created:") {
                            Text(collection.createdAt, style: .date)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Last Updated:") {
                            Text(collection.updatedAt, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }
                
                GroupBox("Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Total Requests:") {
                            Text("\(collection.requests.count)")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Folders:") {
                            Text("\(collection.folders.count)")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Environments:") {
                            Text("\(collection.environments.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct FolderDetailView: View {
    @Bindable var folder: Folder
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                Text(folder.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Folder Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Name:") {
                                TextField("Name", text: $folder.name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledContent("Collection:") {
                                Text(folder.collection?.name ?? "None")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Statistics") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Total Requests:") {
                                Text("\(folder.requests.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
