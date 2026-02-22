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
            .accessibilityLabel("HTTP Method")
            .accessibilityValue(method.rawValue)
            
            HighlightedURLField(
                text: $url,
                placeholder: "Enter request URL",
                onSubmit: {
                    if !isSending {
                        onSend()
                    }
                }
            )
            .frame(height: 22)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .focused($isURLFocused)
            .accessibilityLabel("Request URL")
            .accessibilityHint("Enter the URL for the HTTP request")
            
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
            .accessibilityLabel(isSending ? "Cancel Request" : "Send Request")
            .accessibilityHint(isSending ? "Cancel the in-flight request" : "Send the HTTP request. Shortcut: Command+Return")
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
