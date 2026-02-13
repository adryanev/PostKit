import SwiftUI

struct RequestRow: View {
    let request: HTTPRequest
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(request.method.rawValue)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(methodColor)
                .frame(width: compact ? 50 : 60, alignment: .leading)
            
            Text(request.name)
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
    
    private var methodColor: Color {
        switch request.method {
        case .get: .green
        case .post: .orange
        case .put: .blue
        case .patch: .purple
        case .delete: .red
        case .head, .options: .gray
        }
    }
}

#Preview {
    List {
        RequestRow(request: HTTPRequest(name: "Get Users", method: .get))
        RequestRow(request: HTTPRequest(name: "Create User", method: .post))
        RequestRow(request: HTTPRequest(name: "Delete User", method: .delete))
    }
}
