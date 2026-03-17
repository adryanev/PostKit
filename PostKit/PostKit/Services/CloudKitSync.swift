import Foundation
import SwiftData
import CloudKit
import os
import Combine

// MARK: - CloudKit Sync Service

/// Manages CloudKit synchronization for SwiftData models
@MainActor
final class CloudKitSync: ObservableObject, CloudKitSyncProtocol {
    
    // MARK: - Published Properties
    
    @Published private(set) var status: SyncStatus = .notConfigured
    @Published private(set) var statistics: SyncStatistics = SyncStatistics(
        lastSyncDate: nil,
        pendingChanges: 0,
        accountStatus: .couldNotDetermine
    )
    
    // MARK: - Private Properties
    
    private let log = OSLog(subsystem: "dev.adryanev.PostKit", category: "CloudKitSync")
    private let container = CKContainer(identifier: "iCloud.dev.adryanev.PostKit")
    private var cancellables = Set<AnyCancellable>()
    private var notificationsConfigured = false
    private var lastSyncDate: Date?
    private var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "CloudKitSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "CloudKitSyncEnabled") }
    }
    
    // MARK: - Publishers
    
    private let statusSubject = CurrentValueSubject<SyncStatus, Never>(.notConfigured)
    private let statisticsSubject = CurrentValueSubject<SyncStatistics, Never>(
        SyncStatistics(lastSyncDate: nil, pendingChanges: 0, accountStatus: .couldNotDetermine)
    )
    
    nonisolated var statusPublisher: AnyPublisher<SyncStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }
    
    nonisolated var statisticsPublisher: AnyPublisher<SyncStatistics, Never> {
        statisticsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    nonisolated init() {}
    
    func initialize() async {
        os_log(.info, log: log, "Initializing CloudKit sync")
        
        // Check if sync is enabled
        guard isSyncEnabled else {
            await updateStatus(.disabled)
            return
        }
        
        // Check account status
        let accountStatus = await checkAccountStatus()
        
        switch accountStatus {
        case .available:
            if !notificationsConfigured {
                await setupNotifications()
                notificationsConfigured = true
            }
            await updateStatus(.synced)
            os_log(.info, log: log, "CloudKit sync initialized successfully")
            
        case .noAccount:
            await updateStatus(.notConfigured)
            os_log(.info, log: log, "No iCloud account configured")
            
        case .restricted:
            await updateStatus(.error("iCloud access restricted"))
            os_log(.error, log: log, "iCloud access is restricted")
            
        case .couldNotDetermine:
            await updateStatus(.error("Could not determine iCloud status"))
            os_log(.error, log: log, "Could not determine iCloud account status")
            
        case .temporarilyUnavailable:
            await updateStatus(.offline)
            os_log(.info, log: log, "iCloud temporarily unavailable")
            
        @unknown default:
            await updateStatus(.error("Unknown iCloud status"))
            os_log(.error, log: log, "Unknown iCloud account status")
        }
        
        // Update statistics
        await updateStatistics(accountStatus: accountStatus)
    }
    
    // MARK: - Public Methods
    
    func triggerSync() async {
        guard isSyncEnabled else {
            await updateStatus(.disabled)
            return
        }
        
        await updateStatus(.syncing)
        
        // SwiftData with CloudKit handles sync automatically
        // We just need to wait for the notification
        os_log(.info, log: log, "Manual sync triggered")
    }
    
    func enableSync() async {
        os_log(.info, log: log, "Enabling CloudKit sync")
        isSyncEnabled = true
        await initialize()
    }
    
    func disableSync() async {
        os_log(.info, log: log, "Disabling CloudKit sync")
        isSyncEnabled = false
        cancellables.removeAll()
        notificationsConfigured = false
        await updateStatus(.disabled)
    }
    
    func checkAccountStatus() async -> CKAccountStatus {
        do {
            let status = try await container.accountStatus()
            os_log(.debug, log: log, "iCloud account status: %{public}d", status.rawValue)
            return status
        } catch {
            os_log(.error, log: log, "Failed to check account status: %{public}@", error.localizedDescription)
            return .couldNotDetermine
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() async {
        // Listen for CloudKit sync events
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCloudKitEvent(notification)
            }
            .store(in: &cancellables)
        
        // Listen for network status changes
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.checkConnectivity()
                }
            }
            .store(in: &cancellables)
        
        // Listen for app becoming active (macOS equivalent of willEnterForeground)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.checkConnectivity()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleCloudKitEvent(_ notification: Notification) {
        guard isSyncEnabled else { return }

        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else {
            return
        }
        
        os_log(.debug, log: log, "CloudKit event: type=%{public}d, startDate=%{public}@",
               event.type.rawValue, event.startDate as NSDate)
        
        switch event.type {
        case .setup:
            handleSetupEvent(event)
        case .import:
            handleImportEvent(event)
        case .export:
            handleExportEvent(event)
        @unknown default:
            break
        }
    }
    
    private func handleSetupEvent(_ event: NSPersistentCloudKitContainer.Event) {
        if event.succeeded {
            os_log(.info, log: log, "CloudKit setup succeeded")
            Task { await updateStatus(.synced) }
        } else if let error = event.error {
            os_log(.error, log: log, "CloudKit setup failed: %{public}@", error.localizedDescription)
            Task { await updateStatus(.error(error.localizedDescription)) }
        }
    }
    
    private func handleImportEvent(_ event: NSPersistentCloudKitContainer.Event) {
        if event.succeeded {
            os_log(.info, log: log, "CloudKit import succeeded")
            lastSyncDate = Date()
            Task {
                await updateStatus(.synced)
                await updateStatistics()
            }
        } else if let error = event.error {
            os_log(.error, log: log, "CloudKit import failed: %{public}@", error.localizedDescription)
            Task { await updateStatus(.error(error.localizedDescription)) }
        }
    }
    
    private func handleExportEvent(_ event: NSPersistentCloudKitContainer.Event) {
        if event.succeeded {
            os_log(.info, log: log, "CloudKit export succeeded")
            lastSyncDate = Date()
            Task {
                await updateStatus(.synced)
                await updateStatistics()
            }
        } else if let error = event.error {
            os_log(.error, log: log, "CloudKit export failed: %{public}@", error.localizedDescription)
            Task { await updateStatus(.error(error.localizedDescription)) }
        }
    }
    
    private func checkConnectivity() async {
        guard isSyncEnabled else { return }

        // Simple connectivity check via CKContainer
        let accountStatus = await checkAccountStatus()
        
        if accountStatus == .available {
            if case .offline = status {
                await updateStatus(.synced)
            }
        } else if accountStatus == .temporarilyUnavailable {
            await updateStatus(.offline)
        }
        
        await updateStatistics(accountStatus: accountStatus)
    }
    
    private func updateStatus(_ newStatus: SyncStatus) async {
        status = newStatus
        statusSubject.send(newStatus)
    }
    
    private func updateStatistics(accountStatus: CKAccountStatus? = nil) async {
        let currentAccountStatus = accountStatus ?? await checkAccountStatus()
        
        statistics = SyncStatistics(
            lastSyncDate: lastSyncDate,
            pendingChanges: 0, // SwiftData doesn't expose pending changes directly
            accountStatus: currentAccountStatus
        )
        statisticsSubject.send(statistics)
    }
}

// MARK: - Mock for Testing

final class MockCloudKitSync: CloudKitSyncProtocol {
    var status: SyncStatus = .synced
    var statistics: SyncStatistics = SyncStatistics(lastSyncDate: Date(), pendingChanges: 0, accountStatus: .available)
    
    private let statusSubject = CurrentValueSubject<SyncStatus, Never>(.synced)
    private let statisticsSubject = CurrentValueSubject<SyncStatistics, Never>(
        SyncStatistics(lastSyncDate: Date(), pendingChanges: 0, accountStatus: .available)
    )
    
    var statusPublisher: AnyPublisher<SyncStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }
    
    var statisticsPublisher: AnyPublisher<SyncStatistics, Never> {
        statisticsSubject.eraseToAnyPublisher()
    }
    
    func initialize() async {}
    func triggerSync() async {}
    func enableSync() async { status = .synced; statusSubject.send(status) }
    func disableSync() async { status = .disabled; statusSubject.send(status) }
    func checkAccountStatus() async -> CKAccountStatus { .available }
}
