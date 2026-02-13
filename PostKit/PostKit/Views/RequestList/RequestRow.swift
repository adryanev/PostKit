import SwiftUI

struct RequestRow: View {
    let request: HTTPRequest
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(request.method.rawValue)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(request.method.color)
                .frame(width: compact ? 50 : 60, alignment: .leading)
            
            Text(request.name)
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(request.method.rawValue) \(request.name)")
    }
}

#Preview {
    List {
        RequestRow(request: HTTPRequest(name: "Get Users", method: .get))
        RequestRow(request: HTTPRequest(name: "Create User", method: .post))
        RequestRow(request: HTTPRequest(name: "Delete User", method: .delete))
    }
}
