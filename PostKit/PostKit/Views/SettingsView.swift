import SwiftUI
import FactoryKit

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case sync = "iCloud"
    case about = "About"
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .sync: return "icloud"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @ObservationIgnored @Injected(\.cloudKitSync) private var cloudKitSync
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)
            
            SyncPreferencesView(syncService: cloudKitSync)
                .tabItem {
                    Label("iCloud", systemImage: "icloud")
                }
                .tag(SettingsTab.sync)
            
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @AppStorage("showResponseTiming") private var showResponseTiming = true
    @AppStorage("defaultTimeout") private var defaultTimeout = 30.0
    @AppStorage("followRedirects") private var followRedirects = true
    @AppStorage("maxRedirects") private var maxRedirects = 10
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Request Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Default Timeout:") {
                            HStack(spacing: 8) {
                                Slider(value: $defaultTimeout, in: 5...120, step: 5)
                                    .frame(width: 150)
                                Text("\(Int(defaultTimeout))s")
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Toggle("Follow Redirects", isOn: $followRedirects)
                        
                        if followRedirects {
                            LabeledContent("Max Redirects:") {
                                Stepper("\(maxRedirects)", value: $maxRedirects, in: 1...20)
                            }
                        }
                    }
                    .padding(4)
                }
                
                GroupBox("Response Display") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show Response Timing Breakdown", isOn: $showResponseTiming)
                        
                        Text("Display detailed timing information for DNS, TCP, TLS, and transfer phases.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(4)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - About Settings View

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon and Info
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                    
                    Text("PostKit")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                
                Divider()
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("About PostKit")
                        .font(.headline)
                    
                    Text("PostKit is a native macOS HTTP client for testing and documenting APIs. Built with SwiftUI and designed for macOS.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Divider()
                
                // Links
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resources")
                        .font(.headline)
                    
                    Link(destination: URL(string: "https://github.com/adryanev/postkit")!) {
                        Label("GitHub Repository", systemImage: "link")
                    }
                    
                    Link(destination: URL(string: "https://github.com/adryanev/postkit/issues")!) {
                        Label("Report an Issue", systemImage: "ladybug")
                    }
                    
                    Link(destination: URL(string: "https://github.com/adryanev/postkit/discussions")!) {
                        Label("Discussions", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                
                Divider()
                
                // Technical Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Technical Details")
                        .font(.headline)
                    
                    LabeledContent("SwiftData") {
                        Text("Local + iCloud")
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("Minimum macOS") {
                        Text("14.0 (Sonoma)")
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("Built with") {
                        Text("SwiftUI, SwiftData, CloudKit")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Settings Scene

struct SettingsScene: Scene {
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .frame(width: 500, height: 500)
}
