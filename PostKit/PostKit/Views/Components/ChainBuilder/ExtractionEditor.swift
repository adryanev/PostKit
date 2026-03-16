import SwiftUI

/// Editor for configuring extraction rules from responses
struct ExtractionEditor: View {
    @Binding var rules: [ExtractionRule]
    let onAdd: (ExtractionType) -> Void
    let onRemove: (ExtractionRule) -> Void
    let onUpdate: (ExtractionRule) -> Void
    
    @State private var newRuleType: ExtractionType = .jsonPath
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Extraction Rules")
                    .font(.headline)
                
                Spacer()
                
                // Add Rule Menu
                Menu {
                    ForEach(ExtractionType.allCases, id: \.self) { type in
                        Button {
                            onAdd(type)
                        } label: {
                            Label(type.displayName, systemImage: typeIcon(type))
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            
            if rules.isEmpty {
                emptyState
            } else {
                rulesList
            }
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("No Extraction Rules")
                .font(.headline)
            
            Text("Add rules to extract values from the response")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    // MARK: - Rules List
    
    @ViewBuilder
    private var rulesList: some View {
        VStack(spacing: 8) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                ExtractionRuleRow(
                    rule: binding(for: index),
                    onRemove: { onRemove(rule) }
                )
            }
        }
    }
    
    private func binding(for index: Int) -> Binding<ExtractionRule> {
        Binding(
            get: { rules[index] },
            set: { newValue in
                rules[index] = newValue
                onUpdate(newValue)
            }
        )
    }
    
    private func typeIcon(_ type: ExtractionType) -> String {
        switch type {
        case .jsonPath: return "chevron.left.forwardslash.chevron.right"
        case .regex: return "text.magnifyingglass"
        case .header: return "list.bullet.rectangle"
        case .statusCode: return "number"
        }
    }
}

// MARK: - Extraction Rule Row

struct ExtractionRuleRow: View {
    @Binding var rule: ExtractionRule
    let onRemove: () -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ruleContent
        } label: {
            ruleHeader
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var ruleHeader: some View {
        HStack(spacing: 12) {
            // Type Icon
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            // Rule Name
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name.isEmpty ? "Untitled Rule" : rule.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(rule.name.isEmpty ? .secondary : .primary)
                
                Text(rule.extractionType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Variable Badge
            if !rule.variableName.isEmpty {
                Text("{{\(rule.variableName)}}")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            // Enabled Toggle
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
                .controlSize(.small)
            
            // Delete Button
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var ruleContent: some View {
        VStack(spacing: 12) {
            // Rule Name
            LabeledContent("Name") {
                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Extraction Type
            LabeledContent("Type") {
                Picker("", selection: $rule.extractionType) {
                    ForEach(ExtractionType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            
            // Pattern (not shown for status code)
            if rule.extractionType != .statusCode {
                LabeledContent("Pattern") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(rule.extractionType.placeholder, text: $rule.pattern)
                            .textFieldStyle(.roundedBorder)
                        
                        Text(rule.extractionType.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Variable Name
            LabeledContent("Variable Name") {
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("extractedToken", text: $rule.variableName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: rule.variableName) { _, newValue in
                            // Auto-sanitize: remove spaces and special chars
                            let sanitized = newValue.replacingOccurrences(of: " ", with: "")
                                .replacingOccurrences(of: "{{", with: "")
                                .replacingOccurrences(of: "}}", with: "")
                            if sanitized != newValue {
                                rule.variableName = sanitized
                            }
                        }
                    
                    if !rule.variableName.isEmpty {
                        Text("Use as: {{\(rule.variableName)}}")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // Default Value
            LabeledContent("Default Value") {
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("Optional fallback value", text: $rule.defaultValue ?? "")
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Used when extraction fails")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 12)
    }
    
    private var typeIcon: String {
        switch rule.extractionType {
        case .jsonPath: return "chevron.left.forwardslash.chevron.right"
        case .regex: return "text.magnifyingglass"
        case .header: return "list.bullet.rectangle"
        case .statusCode: return "number"
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State var rules: [ExtractionRule] = [
            ExtractionRule(name: "Token", extractionType: .jsonPath, pattern: "$.data.token", variableName: "authToken"),
            ExtractionRule(name: "User ID", extractionType: .jsonPath, pattern: "$.user.id", variableName: "userId"),
        ]
        
        var body: some View {
            ExtractionEditor(
                rules: $rules,
                onAdd: { type in
                    rules.append(ExtractionRule(name: "New", extractionType: type))
                },
                onRemove: { rule in
                    rules.removeAll { $0.id == rule.id }
                },
                onUpdate: { _ in }
            )
            .padding()
            .frame(width: 500)
        }
    }
    
    return PreviewWrapper()
}
