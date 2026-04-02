import SwiftUI
import SwiftData

/// Individual step view component for use in chains
struct ChainStepView: View {
    let step: ChainStep
    let request: HTTPRequest?
    let result: ChainStepResult?
    let isSelected: Bool
    let isExecuting: Bool
    
    let onTap: () -> Void
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Content
            HStack(spacing: 12) {
                // Step Number
                stepNumber
                
                // Step Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(stepName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let request = request {
                        HStack(spacing: 6) {
                            // Method Badge
                            Text(request.method.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(methodForegroundColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(methodBackgroundColor)
                                .clipShape(Capsule())
                            
                            // URL
                            Text(request.urlTemplate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Status/Result
                statusBadge
                
                // Actions
                actionButtons
            }
            .padding(12)
            
            // Extracted Values Preview
            if let result = result, !result.extractedValues.isEmpty {
                extractedValuesSection(result)
            }
            
            // Error Display
            if let result = result, let error = result.errorMessage {
                errorSection(error)
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 0)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .onTapGesture {
            onTap()
        }
    }
    
    // MARK: - Step Number
    
    @ViewBuilder
    private var stepNumber: some View {
        ZStack {
            Circle()
                .fill(stepNumberBackgroundColor)
                .frame(width: 32, height: 32)
            
            if isExecuting {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Text("\(step.stepOrder + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
    }
    
    // MARK: - Status Badge
    
    @ViewBuilder
    private var statusBadge: some View {
        Group {
            if let result = result {
                if result.success {
                    Label("Success", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Failed", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else if !step.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                onRun()
            } label: {
                Image(systemName: "play")
            }
            .buttonStyle(.borderless)
            .help("Run this step")
            
            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Extractions", systemImage: "pencil")
                }
                
                Button {
                    onRun()
                } label: {
                    Label("Run Step", systemImage: "play")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .menuStyle(.borderlessButton)
        }
    }
    
    // MARK: - Extracted Values Section
    
    @ViewBuilder
    private func extractedValuesSection(_ result: ChainStepResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal, 12)
            
            HStack {
                Text("Extracted Values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(result.extractedValues.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            
            // Show first few values
            let values = Array(result.extractedValues.sorted { $0.key < $1.key }.prefix(3))
            ForEach(values, id: \.key) { key, value in
                HStack {
                    Text("{{\(key)}}")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                    
                    Text("=")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(truncated(value, maxLength: 30))
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .opacity(0.5)
                }
                .padding(.horizontal, 12)
            }
            
            if result.extractedValues.count > 3 {
                Text("+\(result.extractedValues.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
        .background(Color.blue.opacity(0.05))
    }
    
    // MARK: - Error Section
    
    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            .padding(12)
        }
        .background(Color.red.opacity(0.05))
    }
    
    // MARK: - Computed Properties
    
    private var stepName: String {
        if !step.name.isEmpty {
            return step.name
        }
        return request?.name ?? "Unknown Request"
    }
    
    private var stepNumberBackgroundColor: Color {
        if let result = result {
            return result.success ? .green : .red
        }
        if !step.isEnabled {
            return .secondary
        }
        return .blue
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        return Color(.windowBackgroundColor)
    }
    
    private var borderColor: Color {
        isSelected ? .accentColor : .clear
    }
    
    private var methodForegroundColor: Color {
        guard let request = request else { return .primary }
        switch request.method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return Color(red: 0.8, green: 0.6, blue: 0)
        case .delete: return .red
        case .head, .options: return .gray
        }
    }

    private var methodBackgroundColor: Color {
        guard let request = request else { return .clear }
        switch request.method {
        case .get: return Color.blue.opacity(0.15)
        case .post: return Color.green.opacity(0.15)
        case .put: return Color.orange.opacity(0.15)
        case .patch: return Color(red: 0.8, green: 0.6, blue: 0).opacity(0.15)
        case .delete: return Color.red.opacity(0.15)
        case .head, .options: return Color.gray.opacity(0.15)
        }
    }

    // MARK: - Helpers
    
    private func truncated(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        return String(string.prefix(maxLength)) + "..."
    }
}

// MARK: - Compact Step View (for sidebar)

struct CompactChainStepView: View {
    let step: ChainStep
    let request: HTTPRequest?
    let result: ChainStepResult?
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Step Number
            ZStack {
                Circle()
                    .fill(stepNumberColor)
                    .frame(width: 24, height: 24)
                
                Text("\(step.stepOrder + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name.isEmpty ? (request?.name ?? "Step") : step.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let request = request {
                    Text("\(request.method.rawValue) • \(request.urlTemplate)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Result indicator
            if let result = result {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? .green : .red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private var stepNumberColor: Color {
        if let result = result {
            return result.success ? .green : .red
        }
        if !step.isEnabled {
            return .secondary
        }
        return .blue
    }
}

