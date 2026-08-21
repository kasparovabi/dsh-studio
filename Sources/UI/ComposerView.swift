import SwiftUI

struct ComposerView: View {
    @EnvironmentObject var app: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = app.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentOrange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        app.lastError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            if !app.queueItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(app.queueItems) { item in
                            HStack(spacing: 5) {
                                Image(systemName: item.placement == "steering" ? "bolt.fill" : "clock")
                                    .font(.system(size: 9))
                                    .foregroundStyle(item.placement == "steering" ? Color.accentOrange : Color.inkSecondary)
                                Text(item.text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.inkPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 220, alignment: .leading)
                                Button {
                                    app.removeQueued(item)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.04)))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
            }
            if !app.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(app.pendingImages) { image in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let preview = image.preview {
                                        Image(nsImage: preview)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.black.opacity(0.05)
                                    }
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.hairline, lineWidth: 1)
                                )
                                Button {
                                    app.removePendingImage(image)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.white, Color.black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .padding(3)
                            }
                            .help(image.name)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    app.attachImages()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Attach images")
                if app.goal == nil {
                    Button {
                        app.goalSheetOpen = true
                    } label: {
                        Image(systemName: "flag")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Set a goal for this session")
                }
                // A vertical field only reports one line of ideal height to a
                // row that also holds fixed size buttons, so the rest of the
                // text ends up clipped. fixedSize makes the row take the
                // height the text actually needs, up to the line limit.
                TextField("Write a task…", text: $app.composer, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1...12)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .focused($focused)
                    .onSubmit { app.send() }
                if app.running {
                    Button {
                        app.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.red.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    Button {
                        app.send(mode: "queue")
                    } label: {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(sendEnabled ? Color.accentOrange : Color.inkSecondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!sendEnabled)
                    .help("Queue this message for after the current turn")
                }
                Button {
                    app.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(sendEnabled ? Color.accentPurple : Color.inkSecondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .help(app.running ? "Send into the running turn" : "Send")
                .disabled(!sendEnabled)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .card(radius: 18)
        .onAppear { focused = true }
        .sheet(isPresented: $app.goalSheetOpen) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Set a goal")
                    .font(.system(size: 14, weight: .semibold))
                TextField("Objective", text: $app.goalDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .frame(width: 320)
                HStack {
                    Spacer()
                    Button("Cancel") { app.goalSheetOpen = false }
                    Button("Create") { app.createGoal() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(app.goalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
    }

    private var sendEnabled: Bool {
        let hasContent = !app.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !app.pendingImages.isEmpty
        return hasContent && app.selected != nil
    }
}
