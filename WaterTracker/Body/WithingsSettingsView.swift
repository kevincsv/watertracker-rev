import AuthenticationServices
import SwiftUI

/// Connects the user's Withings account with their own developer app.
struct WithingsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var model = BodyModel.shared
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var redirectURI = WithingsCredentials.defaultRedirectURI
    @State private var pastedAddress = ""
    @State private var pendingState: String?
    @State private var working = false
    @State private var message: String?

    private var credentials: WithingsCredentials {
        WithingsCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            redirectURI: redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var usesCustomScheme: Bool {
        guard let scheme = URL(string: credentials.redirectURI)?.scheme?.lowercased() else { return false }
        return scheme != "http" && scheme != "https"
    }

    private var canConnect: Bool {
        !credentials.clientID.isEmpty && !credentials.clientSecret.isEmpty && URL(string: credentials.redirectURI)?.scheme != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The Health app only gets weight, body fat and lean mass from Withings. Connecting your account adds muscle mass, body water, bone mass, visceral fat, basal metabolism and metabolic age.")
                    Text("The app then downloads your measurements from Withings' servers with your own key. It only reads, it uploads nothing about you, and the key stays on this iPhone.")
                        .foregroundStyle(.secondary)
                }

                if model.withingsConnected {
                    Section {
                        LabeledContent("Status", value: String(localized: "Connected"))
                        if let sync = model.lastWithingsSync {
                            LabeledContent("Last sync") {
                                Text(sync, style: .relative)
                            }
                        }
                        Button("Sync now", systemImage: "arrow.clockwise") {
                            Task {
                                working = true
                                await model.reload(forceWithings: true)
                                working = false
                            }
                        }
                        .disabled(working)
                        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                            Task { await model.disconnectWithings() }
                        }
                    }
                } else {
                    Section {
                        TextField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Secret", text: $clientSecret)
                        TextField("Callback URL", text: $redirectURI)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    } header: {
                        Text("Your Withings developer app")
                    } footer: {
                        Text("Create a free app at developer.withings.com (Public API, Health data). Use the callback URL above as its Callback URL, then copy its Client ID and Secret here.")
                    }

                    Section {
                        Button {
                            Task { await connect() }
                        } label: {
                            Label("Connect Withings", systemImage: "link")
                        }
                        .disabled(!canConnect || working)
                    } footer: {
                        if !usesCustomScheme {
                            Text("With a web callback URL, sign in in Safari, then copy the address Withings sends you to and paste it below within 30 seconds.")
                        }
                    }

                    if pendingState != nil {
                        Section("Address after signing in") {
                            TextField("Paste the full address", text: $pastedAddress, axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Finish connecting") {
                                Task { await finishFromPaste() }
                            }
                            .disabled(pastedAddress.isEmpty || working)
                        }
                    }
                }

                if let message = message ?? model.withingsError {
                    Section {
                        Text(message)
                            .foregroundStyle(Theme.food)
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Withings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let saved = model.withingsCredentials {
                    clientID = saved.clientID
                    clientSecret = saved.clientSecret
                    redirectURI = saved.redirectURI
                }
            }
        }
    }

    private func connect() async {
        message = nil
        let credentials = credentials
        model.saveCredentials(credentials)
        let state = UUID().uuidString
        guard let url = WithingsAPI.authorizeURL(credentials: credentials, state: state) else { return }

        if usesCustomScheme, let scheme = URL(string: credentials.redirectURI)?.scheme {
            working = true
            defer { working = false }
            do {
                let callback = try await webAuthenticationSession.authenticate(
                    using: url,
                    callback: .customScheme(scheme),
                    additionalHeaderFields: [:]
                )
                guard let code = WithingsAPI.code(from: callback, state: state) else {
                    message = String(localized: "Withings did not return a sign-in code.")
                    return
                }
                await model.completeSignIn(code: code)
                if model.withingsConnected { dismiss() }
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                message = error.localizedDescription
            }
        } else {
            pendingState = state
            pastedAddress = ""
            _ = await UIApplication.shared.open(url)
        }
    }

    private func finishFromPaste() async {
        guard let state = pendingState,
              let url = URL(string: pastedAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              let code = WithingsAPI.code(from: url, state: state)
        else {
            message = String(localized: "That address has no valid sign-in code. Try connecting again.")
            return
        }
        working = true
        await model.completeSignIn(code: code)
        working = false
        if model.withingsConnected {
            pendingState = nil
            dismiss()
        }
    }
}
