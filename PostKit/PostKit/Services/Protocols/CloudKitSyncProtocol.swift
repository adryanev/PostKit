import Foundation
import CloudKit
import Combine

// MARK: - Sync Status

/// Represents the current state of CloudKit synchronization
enum SyncStatus: Sendable, Equatable {
    case notConfigured
    case disabled
    case syncing
    case synced
    case offline
    case error(String)
    
    var icon: String {
        switch self {
        case .notConfigured: return "icloud.slash"
        case .disabled: return "icloud.slash"
        case .syncing: return "icloud.and.arrow.up.and.down"
        case .synced: return "checkmark.icloud"
        case .offline: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        }
    }
    
    var displayText: String {
        switch self {
        case .notConfigured: return "iCloud Not Configured"
        case .disabled: return "iCloud Sync Disabled"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .offline: return "Offline"
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - Sync Statistics

/// Statistics about the sync state
struct SyncStatistics: Sendable {
    let lastSyncDate: Date?
    let pendingChanges: Int
    let accountStatus: CKAccountStatus
    
    var lastSyncText: String {
        guard let date = lastSyncDate else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - CloudKit Sync Protocol

protocol CloudKitSyncProtocol: Sendable {
    var status: SyncStatus { get }
    var statistics: SyncStatistics { get }
    var statusPublisher: AnyPublisher<SyncStatus, Never> { get }
    var statisticsPublisher: AnyPublisher<SyncStatistics, Never> { get }
    
    func initialize() async
    func triggerSync() async
    func enableSync() async
    func disableSync() async
    func checkAccountStatus() async -> CKAccountStatus
}
