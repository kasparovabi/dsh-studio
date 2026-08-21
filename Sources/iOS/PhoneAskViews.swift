import SwiftUI

struct PhoneActionCapsule: View {
    let label: String
    var glyph: String = "plus"
    var filled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(filled ? .white : Color.phoneInk)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(filled ? Color.phoneSlate : Color.phoneControl))
        }
        .buttonStyle(.plain)
    }
}

struct PhoneApprovalCard: View {
    @EnvironmentObject var app: AppModel
    let approval: ApprovalRequest

    private var arguments: String? {
        guard let callId = approval.callId else { return nil }
        for item in app.items {
            if case .tool(let id, _, _, let detail, _) = item, id == callId {
                return detail.isEmpty ? nil : detail
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.phoneInk)
                Text("Approval required")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.phoneInk)
                Spacer(minLength: 0)
                Text(approval.toolName.sanitizedForDisplay)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.phoneInkSoft)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.phoneCard))
            }
            if let reason = approval.reason, !reason.isEmpty {
                Text(reason.sanitizedForDisplay)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.phoneInkSoft)
            }
            if let args = arguments {
                Text(args.sanitizedForDisplay)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.phoneInkSoft)
                    .lineLimit(4)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                PhoneActionCapsule(label: "Reject", glyph: "xmark", filled: false) {
                    app.respond(to: approval, outcome: "rejected")
                }
                PhoneActionCapsule(label: "Allow once", glyph: "checkmark") {
                    app.respond(to: approval, outcome: "allowed-once")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous)
                .fill(Color.phoneWash)
        )
        .padding(.horizontal, Phone.margin)
        .padding(.bottom, 8)
    }
}

struct PhoneQuestionCard: View {
    @EnvironmentObject var app: AppModel
    let request: QuestionRequest
    @State private var selections: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.phoneInk)
                Text("The agent is asking")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.phoneInk)
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(request.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            if let header = item.header {
                                Text(header.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(Color.phoneStamp)
                            }
                            Text(item.question)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.phoneInk)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.phoneInkSoft)
                            }
                            ForEach(item.options) { option in
                                optionRow(item: item, option: option)
                            }
                            TextField("", text: bindingCustom(item))
                                .placeholder(when: (custom[item.id] ?? "").isEmpty) {
                                    Text("Something else").foregroundStyle(Color.phoneInkSoft)
                                }
                                .font(.system(size: 15))
                                .foregroundStyle(Color.phoneInk)
                                .padding(.horizontal, 14)
                                .frame(height: Phone.control)
                                .background(Capsule().fill(Color.phoneCard))
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            HStack(spacing: 8) {
                PhoneActionCapsule(label: "Skip", glyph: "xmark", filled: false) {
                    app.skipQuestion(request)
                }
                PhoneActionCapsule(
                    label: request.items.first?.approveLabel ?? "Submit",
                    glyph: "checkmark"
                ) {
                    app.answerQuestion(request, selections: selections, custom: custom)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous)
                .fill(Color.phoneWash)
        )
        .padding(.horizontal, Phone.margin)
        .padding(.bottom, 8)
    }

    private func optionRow(item: QuestionItem, option: QuestionOption) -> some View {
        let on = (selections[item.id] ?? []).contains(option.label)
        return Button {
            var set = selections[item.id] ?? []
            if on {
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
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 15, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? .white : Color.phoneInk)
                        .multilineTextAlignment(.leading)
                    if let description = option.description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(on ? .white.opacity(0.75) : Color.phoneInkSoft)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Phone.radiusBubble, style: .continuous)
                    .fill(on ? Color.phoneSlate : Color.phoneCard)
            )
        }
        .buttonStyle(.plain)
    }

    // dsh rejects an answer that carries both a chip and typed text when the
    // question takes one answer, so the two clear each other here rather than
    // failing after the fact.
    private func bindingCustom(_ item: QuestionItem) -> Binding<String> {
        Binding(
            get: { custom[item.id] ?? "" },
            set: { text in
                custom[item.id] = text
                if !item.multiSelect, !text.isEmpty { selections[item.id] = [] }
            }
        )
    }
}
