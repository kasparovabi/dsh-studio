#if os(macOS)
import SwiftUI

// The desk app used to talk to its own machine and nothing else. A session runs
// where its files are, so reaching the other machine from here is the same need
// the phone already had, and it reads the same list.
struct ServersView: View {
    @EnvironmentObject var app: AppModel
    var onDone: () -> Void

    @State private var name = ""
    @State private var address = ""
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MACHINES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.inkSecondary)
            ForEach(app.savedServers) { server in
                row(server)
            }
            Divider().overlay(Color.hairline)
            adder
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            // The address in use is the one this app was told about last, so it
            // belongs in the list rather than being lost the first time it opens.
            if app.savedServers.isEmpty {
                app.savedServers = [SavedServer(name: "This machine", host: "\(app.host):\(app.port)")]
            }
        }
    }

    private func row(_ server: SavedServer) -> some View {
        let selected = app.isConnected(to: server.host)
        return HStack(spacing: 10) {
            Button {
                guard !selected else { return onDone() }
                Task {
                    await app.switchServer(to: server.host)
                    onDone()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? Color.accentGreen : Color.inkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.inkPrimary)
                        Text(server.host)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                app.savedServers.removeAll { $0.host == server.host }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
            }
            .buttonStyle(.plain)
            .disabled(selected)
            .opacity(selected ? 0.3 : 1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.chipFill))
    }

    private var adder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD ANOTHER MACHINE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.inkSecondary)
            Text("The tailnet address of the machine running dsh web, and the key from that machine's ~/.dsh/proxy-token. A machine on this one needs no key.")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            field("Name", text: $name, placeholder: "Windows")
            field("Address", text: $address, placeholder: "100.64.0.1:3080")
            field("Access key", text: $key, placeholder: "from ~/.dsh/proxy-token")
            Button { add() } label: {
                Text("Add and connect")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.onInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(canAdd ? Color.inkPrimary : Color.inkSecondary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.inkSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.inkPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.chipFillStrong))
        }
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Adding a machine and then having to pick it from the list reads as if
    // nothing happened, so the entry and the connection are one step.
    private func add() {
        let server = SavedServer(
            name: name.trimmingCharacters(in: .whitespaces),
            host: address.trimmingCharacters(in: .whitespaces)
        )
        app.savedServers.removeAll { $0.host == server.host }
        app.savedServers.append(server)
        let parsed = AppModel.splitAddress(server.host, fallbackPort: app.port)
        AppModel.setAccessToken(
            key.trimmingCharacters(in: .whitespaces),
            forHost: parsed.host,
            port: parsed.port
        )
        name = ""
        address = ""
        key = ""
        Task {
            await app.switchServer(to: server.host)
            onDone()
        }
    }
}
#endif
