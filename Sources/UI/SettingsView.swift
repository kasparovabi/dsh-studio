import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(Color.accentPurple)
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if app.settingsBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Close") { app.settingsOpen = false }
            }

            if let notice = app.settingsNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providerCredentials
                    defaultModel
                    footnote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .onAppear { if app.credentialRows.isEmpty { Task { await app.loadSettings() } } }
    }

    private var providerCredentials: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Provider keys")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
            Text("Enter an API key or token for any provider your models use. Keys are stored by dsh in ~/.dsh/.credentials.yaml and take effect on the next request.")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)

            ForEach(app.credentialRows) { row in
                credentialCard(row)
            }
        }
    }

    private func credentialCard(_ row: CredentialRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(row.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                Text(row.ref)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                statusBadge(row)
            }

            if row.configured, !row.writable {
                Text("Provided by your environment, read-only here. Unset it in your shell or ~/.hermes/.env to manage it from this panel.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.inkSecondary)
            } else {
                HStack(spacing: 8) {
                    SecureField(row.configured ? "Enter a new key to replace" : "Paste key or token",
                                text: draftBinding(row.ref))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button("Save") { app.saveCredential(row.ref) }
                        .disabled(app.settingsBusy || (app.credentialDrafts[row.ref] ?? "").isEmpty)
                    if row.configured {
                        Button(role: .destructive) { app.clearCredential(row.ref) } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(app.settingsBusy)
                        .help("Remove stored key")
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    private func statusBadge(_ row: CredentialRow) -> some View {
        let configured = row.configured
        let label = configured ? (row.writable ? "Configured" : "From environment") : "Not set"
        let tint = configured ? Color.accentGreen : Color.inkSecondary
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var defaultModel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default model")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
            Text("Provider and model a new session starts with.")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
            HStack(spacing: 8) {
                TextField("provider", text: $app.settingsProvider)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 150)
                TextField("model", text: $app.settingsModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("Save") { app.saveDefaultModel() }
                    .disabled(app.settingsBusy || app.settingsProvider.isEmpty || app.settingsModel.isEmpty)
            }
        }
    }

    private var footnote: some View {
        Text("dsh reads each provider's key from the reference named by apiKeyEnv in ~/.dsh/settings.yaml. Adding a brand-new provider still needs its block there; this panel manages the keys those references point to.")
            .font(.system(size: 10))
            .foregroundStyle(Color.inkSecondary)
    }

    private func draftBinding(_ ref: String) -> Binding<String> {
        Binding(
            get: { app.credentialDrafts[ref] ?? "" },
            set: { app.credentialDrafts[ref] = $0 }
        )
    }
}
