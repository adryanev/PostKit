import SwiftUI

struct URLBar: View {
    @Binding var method: HTTPMethod
    @Binding var url: String
    let isSending: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isURLFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Picker("Method", selection: $method) {
                ForEach(HTTPMethod.allCases, id: \.self) { method in
                    Text(method.rawValue)
                        .tag(method)
                }
            }
            .frame(width: 90)
            .labelsHidden()
            
            TextField("Enter request URL", text: $url)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .focused($isURLFocused)
                .onSubmit {
                    if !isSending {
                        onSend()
                    }
                }
            
            Button(action: isSending ? onCancel : onSend) {
                if isSending {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Cancel")
                    }
                } else {
                    Text("Send")
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minWidth: 70)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    URLBar(
        method: .constant(.get),
        url: .constant("https://api.example.com/users"),
        isSending: false,
        onSend: {},
        onCancel: {}
    )
    .padding()
}
