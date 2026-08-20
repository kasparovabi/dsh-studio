import SwiftUI

struct SessionGroup: Identifiable {
    var id: SessionBucket { bucket }
    let bucket: SessionBucket
    let rows: [SessionRow]
}

struct BucketHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.6)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkSecondary.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial)
    }
}

struct SidebarView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.hairline).padding(.horizontal, 16)
            newSessionButton
            searchField
            projectMenu
            Text("Sessions")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.7)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedSessions, id: \.bucket) { group in
                        Section {
                            ForEach(group.rows) { session in
                                SessionRowView(
                                    session: session,
                                    selected: session.id == app.selected,
                                    snippet: app.searchResults?[session.id]
                                )
                                .onTapGesture {
                                    Task { await app.select(session.id) }
                                }
                                .contextMenu {
                                    Button("Rename…") { app.beginRename(session) }
                                    Button("Fork") { app.fork(session) }
                                }
                            }
                        } header: {
                            BucketHeader(title: group.bucket.rawValue, count: group.rows.count)
                        }
                    }
                    if app.searchResults != nil && visibleSessions.isEmpty {
                        Text("No matches")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkSecondary)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxHeight: .infinity)
        .card(radius: 20)
        .sheet(item: $app.renameTarget) { target in
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename session")
                    .font(.system(size: 14, weight: .semibold))
                TextField("Title", text: $app.renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit { app.commitRename() }
                HStack {
                    Spacer()
                    Button("Cancel") { app.renameTarget = nil }
                    Button("Rename") { app.commitRename() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(app.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .presentationBackground(.regularMaterial)
            .onAppear { _ = target }
        }
    }

    private var visibleSessions: [SessionRow] {
        var rows = app.sessions
        if let project = app.projectFilter {
            rows = rows.filter { $0.project == project }
        }
        let query = app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        let matched = app.searchResults ?? [:]
        return rows.filter {
            matched.keys.contains($0.id)
                || $0.title.localizedCaseInsensitiveContains(query)
                || $0.cwd.localizedCaseInsensitiveContains(query)
        }
    }

    private var projectMenu: some View {
        Menu {
            Button {
                app.projectFilter = nil
            } label: {
                Label("All projects (\(app.sessions.count))", systemImage: app.projectFilter == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(app.projectCounts, id: \.name) { entry in
                Button {
                    app.projectFilter = entry.name
                } label: {
                    Label("\(entry.name) (\(entry.count))",
                          systemImage: app.projectFilter == entry.name ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                Text(app.projectFilter ?? "All projects")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.inkSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var groupedSessions: [SessionGroup] {
        let rows = visibleSessions
        return SessionBucket.allCases.compactMap { bucket in
            let matching = rows.filter { $0.bucket == bucket }
            return matching.isEmpty ? nil : SessionGroup(bucket: bucket, rows: matching)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
            TextField("Search sessions", text: $app.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onChange(of: app.searchQuery) {
                    app.runSearch()
                }
            if !app.searchQuery.isEmpty {
                Button {
                    app.searchQuery = ""
                    app.searchResults = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [.accentPurple, Color(hex: 0xB07CFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
                .overlay(Text("dsh").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("DSH Studio")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var statusColor: Color {
        switch app.serverState {
        case .ready: return app.wsConnected ? .accentGreen : .accentOrange
        case .failed: return .red
        default: return .accentOrange
        }
    }

    private var statusText: String {
        switch app.serverState {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .launching: return "Starting server"
        case .ready: return app.wsConnected ? "Connected" : "Stream lost"
        case .failed(let m): return m
        }
    }

    private var newSessionButton: some View {
        Button {
            app.newSession()
        } label: {
            HStack {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("New session")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.inkPrimary))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Color.hairline)
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.model.isEmpty ? "No model" : app.model)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(1)
                    Text(app.provider)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

struct SessionRowView: View {
    let session: SessionRow
    let selected: Bool
    var snippet: String?

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(chipColor.opacity(selected ? 0.9 : 0.55))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if session.running {
                        Circle()
                            .fill(Color.accentGreen)
                            .frame(width: 6, height: 6)
                    }
                    Text(session.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(1)
                }
                if let snippet {
                    Text(snippet)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(shortPath)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                    if !session.relativeTime.isEmpty {
                        Text("·").foregroundStyle(Color.inkSecondary.opacity(0.5))
                        Text(session.relativeTime)
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    }
                    if session.turns > 0 {
                        Text("·").foregroundStyle(Color.inkSecondary.opacity(0.5))
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 8))
                            Text("\(session.turns)")
                        }
                        .foregroundStyle(Color.inkSecondary)
                    }
                }
                .font(.system(size: 10))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.black.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var shortPath: String {
        let parts = session.cwd.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    private var chipColor: Color {
        let palette: [Color] = [.accentPurple, .accentOrange, .accentTeal, .accentGreen]
        var hash: UInt64 = 5381
        for byte in session.cwd.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
