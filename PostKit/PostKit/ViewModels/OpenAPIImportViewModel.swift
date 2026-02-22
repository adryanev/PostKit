import Foundation
import SwiftData
import Observation
import SwiftUI

enum ImportStep: Int, CaseIterable, Sendable {
    case fileSelect = 0
    case target = 1
    case configure = 2
    case conflicts = 3
    
    var title: String {
        switch self {
        case .fileSelect: return "Select File"
        case .target: return "Choose Target"
        case .configure: return "Configure"
        case .conflicts: return "Review Changes"
        }
    }
}

enum ImportMode: Sendable, Equatable {
    case createNew
    case updateExisting(RequestCollection)
    
    static func == (lhs: ImportMode, rhs: ImportMode) -> Bool {
        switch (lhs, rhs) {
        case (.createNew, .createNew):
            return true
        case (.updateExisting(let l), .updateExisting(let r)):
            return l.id == r.id
        default:
            return false
        }
    }
}

enum NavigationDirection {
    case forward
    case backward
}

@Observable
final class OpenAPIImportViewModel {
    var currentStep: ImportStep = .fileSelect
    private(set) var navigationDirection: NavigationDirection = .forward
    
    var spec: OpenAPISpec?
    var importMode: ImportMode = .createNew
    var selectedEndpoints: Set<String> = []
    var diffResult: DiffResult?
    var endpointDecisions: [String: EndpointDecision] = [:]
    var refSkipWarning: String?
    
    var parseError: String?
    var isLoading = false
    var fileURL: URL?
    
    var collections: [RequestCollection] = []
    
    private let parser = OpenAPIParser()
    private let diffEngine = OpenAPIDiffEngine()
    
    var effectiveLastStep: ImportStep {
        switch importMode {
        case .createNew:
            return .configure
        case .updateExisting:
            return .conflicts
        }
    }
    
    var canGoNext: Bool {
        switch currentStep {
        case .fileSelect:
            return spec != nil && parseError == nil
        case .target:
            return true
        case .configure:
            return !selectedEndpoints.isEmpty
        case .conflicts:
            return true
        }
    }
    
    var canGoBack: Bool {
        return currentStep != .fileSelect
    }
    
    var isLastStep: Bool {
        currentStep == effectiveLastStep
    }
    
    var isUpdateMode: Bool {
        if case .updateExisting = importMode {
            return true
        }
        return false
    }
    
    func parseFile(at url: URL) {
        fileURL = url
        parseError = nil
        spec = nil
        diffResult = nil
        endpointDecisions = [:]
        refSkipWarning = nil
        isLoading = true
        
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                let parsedSpec = try parser.parseSpec(data)
                
                self.spec = parsedSpec
                self.selectedEndpoints = Set(parsedSpec.endpoints.map { $0.id })
                
                if parsedSpec.refSkipCount > 0 {
                    self.refSkipWarning = "\(parsedSpec.refSkipCount) parameter(s) use $ref and were skipped"
                }
            } catch {
                self.parseError = error.localizedDescription
            }
            self.isLoading = false
        }
    }
    
    func goNext() {
        guard canGoNext else { return }
        
        if currentStep == .configure && isUpdateMode {
            runDiff()
        }
        
        if currentStep.rawValue < effectiveLastStep.rawValue {
            navigationDirection = .forward
            withAnimation(.easeInOut(duration: 0.25)) {
                currentStep = ImportStep(rawValue: currentStep.rawValue + 1) ?? currentStep
            }
        }
    }
    
    func goBack() {
        guard canGoBack else { return }
        
        if currentStep.rawValue > 0 {
            navigationDirection = .backward
            withAnimation(.easeInOut(duration: 0.25)) {
                currentStep = ImportStep(rawValue: currentStep.rawValue - 1) ?? currentStep
            }
        }
    }
    
    func selectAllEndpoints() {
        guard let spec else { return }
        selectedEndpoints = Set(spec.endpoints.map { $0.id })
    }
    
    func deselectAllEndpoints() {
        selectedEndpoints = []
    }
    
    func runDiff() {
        guard let spec,
              case .updateExisting(let collection) = importMode else { return }
        
        let existingSnapshots = collection.requests
            .filter { $0.openAPIPath != nil }
            .map { diffEngine.createSnapshotFromRequest($0) }
        
        let selectedEndpointList = spec.endpoints.filter { selectedEndpoints.contains($0.id) }
        
        diffResult = diffEngine.diff(
            spec: spec,
            selectedEndpoints: selectedEndpointList,
            serverURL: "{{baseUrl}}",
            existingSnapshots: existingSnapshots,
            securitySchemes: spec.securitySchemes
        )
        
        endpointDecisions = [:]
        
        for endpoint in diffResult?.newEndpoints ?? [] {
            endpointDecisions[endpoint.id] = .addNew(endpoint)
        }
        
        for change in diffResult?.changedEndpoints ?? [] {
            if let requestID = change.existing.requestID {
                endpointDecisions[change.id] = .keepExisting(requestID: requestID)
            }
        }
        
        for snapshot in diffResult?.removedEndpoints ?? [] {
            if let requestID = snapshot.requestID {
                endpointDecisions[snapshot.id] = .keepExisting(requestID: requestID)
            }
        }
        
        for snapshot in diffResult?.unchangedEndpoints ?? [] {
            if let requestID = snapshot.requestID {
                endpointDecisions[snapshot.id] = .keepExisting(requestID: requestID)
            }
        }
    }
    
    func setDecision(for endpointID: String, decision: EndpointDecision) {
        endpointDecisions[endpointID] = decision
    }
    
    func performImport(context: ModelContext) throws {
        guard let spec else { return }
        
        let importer = OpenAPIImporter()
        let selectedEndpointList = spec.endpoints.filter { selectedEndpoints.contains($0.id) }
        
        switch importMode {
        case .createNew:
            _ = try importer.importNewCollection(
                spec: spec,
                selectedEndpoints: selectedEndpointList,
                into: context
            )
            
        case .updateExisting(let collection):
            let decisions = Array(endpointDecisions.values)
            try importer.updateCollection(
                collection,
                decisions: decisions,
                spec: spec,
                selectedEndpoints: selectedEndpointList,
                context: context
            )
        }
    }
    
    func loadCollections(context: ModelContext) {
        let descriptor = FetchDescriptor<RequestCollection>(sortBy: [SortDescriptor(\.name)])
        collections = (try? context.fetch(descriptor)) ?? []
    }
    
    func reset() {
        currentStep = .fileSelect
        spec = nil
        parseError = nil
        fileURL = nil
        diffResult = nil
        endpointDecisions = [:]
        refSkipWarning = nil
        selectedEndpoints = []
        importMode = .createNew
    }
}
