import SwiftUI

struct QuestionCard: View {
    @EnvironmentObject var app: AppModel
    let request: QuestionRequest
    @State private var selections: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentPurple)
                Text("The agent is asking")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
            }
            ForEach(request.items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    if let header = item.header {
                        Text(header)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentPurple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentPurple.opacity(0.10)))
                    }
                    Text(item.question)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkPrimary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    if !item.options.isEmpty {
                        FlowChips(item: item, selections: $selections, custom: $custom)
                    }
                    TextField("Other…", text: bindingCustom(item))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.black.opacity(0.03))
                        )
                }
            }
            HStack {
                Spacer()
                Button {
                    app.skipQuestion(request)
                } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Let the agent continue without an answer")
                Button {
                    app.answerQuestion(request, selections: selections, custom: custom)
                } label: {
                    Text(request.items.first?.approveLabel ?? "Submit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(submitEnabled ? Color.accentPurple : Color.inkSecondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .disabled(!submitEnabled)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentPurple.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentPurple.opacity(0.22), lineWidth: 1)
        )
    }

    private var submitEnabled: Bool {
        request.items.allSatisfy { item in
            !(selections[item.id] ?? []).isEmpty || !(custom[item.id] ?? "").isEmpty || item.options.isEmpty
        }
    }

    // dsh rejects an answer that carries both a chip and typed text when the
    // question takes one answer, so the two clear each other here rather than
    // failing after the fact.
    private func bindingCustom(_ item: QuestionItem) -> Binding<String> {
        Binding(
            get: { custom[item.id] ?? "" },
            set: { text in
                custom[item.id] = text
                if !item.multiSelect, !text.isEmpty {
                    selections[item.id] = []
                }
            }
        )
    }
}

struct FlowChips: View {
    let item: QuestionItem
    @Binding var selections: [String: Set<String>]
    @Binding var custom: [String: String]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(item.options) { option in
                let isOn = (selections[item.id] ?? []).contains(option.label)
                Button {
                    var set = selections[item.id] ?? []
                    if isOn {
                        set.remove(option.label)
                    } else {
                        if !item.multiSelect {
                            set.removeAll()
                            custom[item.id] = ""
                        }
                        set.insert(option.label)
                    }
                    selections[item.id] = set
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.label)
                            .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? Color.white : Color.inkPrimary)
                        if let desc = option.description {
                            Text(desc)
                                .font(.system(size: 10))
                                .foregroundStyle(isOn ? Color.white.opacity(0.8) : Color.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isOn ? Color.accentPurple : Color.black.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
