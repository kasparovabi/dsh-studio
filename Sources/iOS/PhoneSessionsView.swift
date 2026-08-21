import SwiftUI

struct PhoneSessionsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var newSessionOpen = false

    var body: some View {
        ZStack {
            Color.phoneGround.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                PhoneSearchField(text: $query)
                    .padding(.horizontal, Phone.margin)
                list
            }
            .padding(.top, 14)
        }
        .sheet(isPresented: $newSessionOpen) {
            PhoneNewSessionView { cwd in
                newSessionOpen = false
                Task {
                    await app.createSession(cwd: cwd)
                    dismiss()
                }
            }
            .environmentObject(app)
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Sessions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.phoneInk)
            Spacer()
            Button { newSessionOpen = true } label: {
                CircleControl(system: "plus")
            }
            Button { dismiss() } label: {
                CircleControl(system: "xmark")
            }
        }
        .padding(.horizontal, Phone.margin)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(buckets, id: \.0) { bucket, rows in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(bucket.rawValue.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Color.phoneStamp)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                Button {
                                    Task {
                                        await app.select(row.id)
                                        dismiss()
                                    }
                                } label: {
                                    PhoneSessionRow(row: row, current: row.id == app.selected)
                                }
                                .buttonStyle(.plain)
                                if row.id != rows.last?.id {
                                    Divider().overlay(Color.phoneWash).padding(.leading, 16)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous)
                                .fill(Color.phoneCard)
                        )
                    }
                }
                if app.sessions.isEmpty {
                    Text(app.serverState == .ready ? "No sessions yet" : app.serverStatusText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.phoneInkSoft)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, Phone.margin)
            .padding(.bottom, 30)
        }
        .refreshable { await app.refreshSessions() }
    }

    private var buckets: [(SessionBucket, [SessionRow])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = needle.isEmpty ? app.sessions : app.sessions.filter {
            $0.title.lowercased().contains(needle) || $0.project.lowercased().contains(needle)
        }
        return SessionBucket.allCases.compactMap { bucket in
            let group = rows.filter { $0.bucket == bucket }
            return group.isEmpty ? nil : (bucket, group)
        }
    }
}

struct PhoneSessionRow: View {
    let row: SessionRow
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(row.running ? Color.phoneGreen : Color.phoneWash)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 15, weight: current ? .semibold : .regular))
                    .foregroundStyle(Color.phoneInk)
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.phoneInkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if current {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.phoneInk)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts = [row.project]
        if row.turns > 0 { parts.append("\(row.turns) turns") }
        let time = row.relativeTime
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: " · ")
    }
}

struct PhoneSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.phoneInkSoft)
            TextField("", text: $text)
                .placeholder(when: text.isEmpty) {
                    Text("Search sessions").foregroundStyle(Color.phoneInkSoft)
                }
                .font(.system(size: 15))
                .foregroundStyle(Color.phoneInk)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.phoneInkSoft)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Phone.control)
        .background(Capsule().fill(Color.phoneControl))
    }
}

struct PhoneNewSessionView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    let start: (String) -> Void

    var body: some View {
        ZStack {
            Color.phoneGround.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("New session")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.phoneInk)
                    Spacer()
                    Button { dismiss() } label: { CircleControl(system: "xmark") }
                }
                Text("PICK A DIRECTORY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.phoneStamp)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(directories, id: \.self) { path in
                            Button { start(path) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.phoneInkSoft)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text((path as NSString).lastPathComponent)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.phoneInk)
                                        Text(path)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.phoneInkSoft)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if path != directories.last {
                                Divider().overlay(Color.phoneWash).padding(.leading, 16)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous)
                            .fill(Color.phoneCard)
                    )
                }
                HStack(spacing: 8) {
                    TextField("", text: $custom)
                        .placeholder(when: custom.isEmpty) {
                            Text("Another path").foregroundStyle(Color.phoneInkSoft)
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(Color.phoneInk)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .frame(height: Phone.control)
                        .background(Capsule().fill(Color.phoneControl))
                    Button {
                        let path = custom.trimmingCharacters(in: .whitespaces)
                        guard !path.isEmpty else { return }
                        start(path)
                    } label: {
                        Text("Open")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: Phone.control)
                            .background(Capsule().fill(Color.phoneSlate))
                    }
                }
            }
            .padding(.horizontal, Phone.margin)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
    }

    private var directories: [String] {
        var seen: [String] = []
        if !app.hostCwd.isEmpty { seen.append(app.hostCwd) }
        for session in app.sessions where !session.cwd.isEmpty {
            if !seen.contains(session.cwd) { seen.append(session.cwd) }
        }
        return seen
    }
}

struct PhoneConnectView: View {
    @EnvironmentObject var app: AppModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.phoneInkSoft)
            Text(app.serverStatusText)
                .font(.system(size: 15))
                .foregroundStyle(Color.phoneInk)
                .multilineTextAlignment(.center)
            Text("Enter the address of the machine running dsh web.")
                .font(.system(size: 13))
                .foregroundStyle(Color.phoneInkSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                TextField("", text: $draft)
                    .placeholder(when: draft.isEmpty) {
                        Text("100.64.0.1").foregroundStyle(Color.phoneInkSoft)
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.phoneInk)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .padding(.horizontal, 14)
                    .frame(height: Phone.control)
                    .background(Capsule().fill(Color.phoneControl))
                Button { retry() } label: {
                    Text("Connect")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: Phone.control)
                        .background(Capsule().fill(Color.phoneSlate))
                }
            }
        }
        .padding(.horizontal, 28)
        .onAppear { if draft.isEmpty { draft = app.host } }
    }

    private func retry() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        app.host = value
        UserDefaults.standard.set(value, forKey: "dsh.host")
        Task { await app.connect() }
    }
}
