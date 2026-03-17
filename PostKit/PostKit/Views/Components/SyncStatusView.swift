import SwiftUI
import Combine

// MARK: - Sync Status View

/// A compact view showing the current sync status in the toolbar
struct SyncStatusView: View {
    @StateObject private var viewModel: SyncStatusViewModel
    
    init(syncService: CloudKitSyncProtocol) {
        _viewModel = StateObject(wrappedValue: SyncStatusViewModel(syncService: syncService))
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.status.icon)
                .symbolEffect(.pulse, isActive: viewModel.status == .syncing)
                .foregroundStyle(iconColor)
            
            if viewModel.showDetails {
                Text(viewModel.status.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(viewModel.tooltip)
        .onTapGesture {
            viewModel.showDetails.toggle()
        }
        .contextMenu {
            syncContextMenu
        }
    }
    
    @ViewBuilder
    private var syncContextMenu: some View {
        Button {
            Task { await viewModel.triggerSync() }
        } label: {
            Label("Sync Now", systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.status == .syncing || viewModel.status == .disabled)
        
        Divider()
        
        if let lastSync = viewModel.statistics.lastSyncDate {
            Text("Last synced: \(lastSync, style: .relative)")
        } else {
            Text("Never synced")
        }
        
        Divider()
        
        Button {
            viewModel.openPreferences()
        } label: {
            Label("iCloud Settings...", systemImage: "gear")
        }
    }
    
    private var iconColor: Color {
        switch viewModel.status {
        case .synced:
            return .green
        case .syncing:
            return .blue
        case .offline, .notConfigured, .disabled:
            return .secondary
        case .error:
            return .red
        }
    }
}

// MARK: - Sync Status View Model

@MainActor
final class SyncStatusViewModel: ObservableObject {
    @Published var status: SyncStatus = .notConfigured
    @Published var statistics: SyncStatistics = SyncStatistics(
        lastSyncDate: nil,
        pendingChanges: 0,
        accountStatus: .couldNotDetermine
    )
    @Published var showDetails = false
    
    private let syncService: CloudKitSyncProtocol
    private var cancellables = Set<AnyCancellable>()
    
    var tooltip: String {
        switch status {
        case .synced:
            if let date = statistics.lastSyncDate {
                let formatter = RelativeDateTimeFormatter()
                return "All changes synced (last: \(formatter.localizedString(for: date, relativeTo: Date())))"
            }
            return "All changes synced"
        case .syncing:
            return "Syncing changes..."
        case .offline:
            return "Offline - changes will sync when connected"
        case .notConfigured:
            return "iCloud not configured"
        case .disabled:
            return "iCloud sync is disabled"
        case .error(let message):
            return "Sync error: \(message)"
        }
    }
    
    init(syncService: CloudKitSyncProtocol) {
        self.syncService = syncService
        
        // Subscribe to sync service updates
        syncService.statusPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)
        
        syncService.statisticsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$statistics)
        
        // Initialize sync service
        Task {
            await syncService.initialize()
        }
    }
    
    func triggerSync() async {
        await syncService.triggerSync()
    }
    
    func openPreferences() {
        // Open preferences to the iCloud pane
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Sync Preferences View

/// Preferences pane for iCloud sync settings
struct SyncPreferencesView: View {
    @StateObject private var viewModel: SyncPreferencesViewModel
    @State private var showingConfirmDisable = false
    
    init(syncService: CloudKitSyncProtocol) {
        _viewModel = StateObject(wrappedValue: SyncPreferencesViewModel(syncService: syncService))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Enable/Disable Toggle
            GroupBox("iCloud Sync") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("Enable iCloud Sync", isOn: $viewModel.isSyncEnabled)
                            .onChange(of: viewModel.isSyncEnabled) { _, newValue in
                                Task {
                                    if newValue {
                                        await viewModel.enableSync()
                                    } else {
                                        await viewModel.disableSync()
                                    }
                                }
                            }
                        Spacer()
                        syncStatusBadge
                    }
                    
                    Text("Sync your collections, requests, and environments across all your Macs using iCloud.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if !viewModel.isSignedIn {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Sign in to iCloud in System Settings to enable sync.")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(4)
            }
            
            // Sync Status Details
            if viewModel.isSyncEnabled {
                GroupBox("Sync Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: viewModel.status.icon)
                                .foregroundStyle(statusColor)
                            Text(viewModel.status.displayText)
                                .font(.body)
                            Spacer()
                        }
                        
                        Divider()
                        
                        LabeledContent("Last Sync:") {
                            Text(viewModel.lastSyncText)
                                .foregroundStyle(.secondary)
                        }
                        
                        LabeledContent("Account:") {
                            Text(viewModel.accountStatusText)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        HStack {
                            Button("Sync Now") {
                                Task { await viewModel.triggerSync() }
                            }
                            .disabled(viewModel.status == .syncing)
                            
                            Spacer()
                        }
                    }
                    .padding(4)
                }
            }
            
            // Danger Zone
            if viewModel.isSyncEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Disabling sync will keep your data locally but stop syncing to iCloud.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button("Disable iCloud Sync", role: .destructive) {
                            showingConfirmDisable = true
                        }
                        .confirmationDialog(
                            "Disable iCloud Sync?",
                            isPresented: $showingConfirmDisable,
                            titleVisibility: .visible
                        ) {
                            Button("Disable", role: .destructive) {
                                Task { await viewModel.disableSync() }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Your data will remain on this Mac but won't sync to other devices. Data on other devices will remain unchanged.")
                        }
                    }
                    .padding(4)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private var syncStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.status.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var statusColor: Color {
        switch viewModel.status {
        case .synced:
            return .green
        case .syncing:
            return .blue
        case .offline, .notConfigured, .disabled:
            return .secondary
        case .error:
            return .red
        }
    }
}

// MARK: - Sync Preferences View Model

@MainActor
final class SyncPreferencesViewModel: ObservableObject {
    @Published var isSyncEnabled = false
    @Published var isSignedIn = false
    @Published var status: SyncStatus = .notConfigured
    @Published var statistics: SyncStatistics = SyncStatistics(
        lastSyncDate: nil,
        pendingChanges: 0,
        accountStatus: .couldNotDetermine
    )
    
    private let syncService: CloudKitSyncProtocol
    private var cancellables = Set<AnyCancellable>()
    
    var lastSyncText: String {
        statistics.lastSyncText
    }
    
    var accountStatusText: String {
        switch statistics.accountStatus {
        case .available:
            return "Signed In"
        case .noAccount:
            return "No Account"
        case .restricted:
            return "Restricted"
        case .couldNotDetermine:
            return "Unknown"
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        @unknown default:
            return "Unknown"
        }
    }
    
    init(syncService: CloudKitSyncProtocol) {
        self.syncService = syncService
        
        // Subscribe to updates
        syncService.statusPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)
        
        syncService.statisticsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$statistics)
        
        // Initialize
        Task {
            await initialize()
        }
    }
    
    private func initialize() async {
        await syncService.initialize()
        isSyncEnabled = syncService.status != .disabled && syncService.status != .notConfigured
        isSignedIn = syncService.statistics.accountStatus == .available
    }
    
    func enableSync() async {
        await syncService.enableSync()
        isSyncEnabled = true
        isSignedIn = syncService.statistics.accountStatus == .available
    }
    
    func disableSync() async {
        await syncService.disableSync()
        isSyncEnabled = false
    }
    
    func triggerSync() async {
        await syncService.triggerSync()
    }
}

// MARK: - Previews

#Preview("Sync Status View") {
    HStack {
        SyncStatusView(syncService: MockCloudKitSync())
        Spacer()
    }
    .padding()
}

#Preview("Sync Preferences") {
    SyncPreferencesView(syncService: MockCloudKitSync())
        .frame(width: 400, height: 500)
}
