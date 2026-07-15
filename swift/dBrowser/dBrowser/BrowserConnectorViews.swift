import SwiftUI

struct BrowserConnectorSectionView: View {
    @ObservedObject var coordinator: BrowserConnectorCoordinator
    @Environment(\.openURL) private var openURL

    @State private var gmailQuery = "newer_than:7d"
    @State private var draftTo = ""
    @State private var draftCC = ""
    @State private var draftBCC = ""
    @State private var draftSubject = ""
    @State private var draftBody = ""
    @State private var eventCalendarID = "primary"
    @State private var eventTitle = ""
    @State private var eventStart = Date().addingTimeInterval(3_600)
    @State private var eventEnd = Date().addingTimeInterval(7_200)
    @State private var eventTimeZone = TimeZone.current.identifier
    @State private var eventLocation = ""
    @State private var eventNotes = ""
    @State private var localError: String?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                Text(coordinator.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(coordinator.profiles) { profile in
                    connectorCard(profile)
                }

                ForEach(coordinator.mutationProposals) { proposal in
                    mutationReview(proposal)
                }

                if let localError {
                    Label(localError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Gmail & Calendar connectors", systemImage: "link.badge.plus")
                .font(.headline)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("copilot-connectors")
    }

    @ViewBuilder
    private func connectorCard(_ profile: BrowserConnectorProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(profile.connectionState.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if profile.connectionState == .connected {
                    Button("Disconnect") {
                        coordinator.disconnect(profile.kind)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        beginAuthorization(profile.kind)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.oauthConfiguration.isConfigured || coordinator.isWorking)
                }
            }

            Text(scopeSummary(profile.kind))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if profile.connectionState == .configurationRequired {
                Text("Provide DBROWSER_GOOGLE_OAUTH_CLIENT_ID and register the app callback exactly as dbrowser://oauth/google.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if profile.connectionState == .connected {
                switch profile.kind {
                case .gmail:
                    gmailActions(profile)
                case .googleCalendar:
                    calendarActions(profile)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func gmailActions(_ profile: BrowserConnectorProfile) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                TextField("Gmail search", text: $gmailQuery)
                    .textFieldStyle(.roundedBorder)
                Button("Search") {
                    Task { await coordinator.searchGmail(gmailQuery) }
                }
                .buttonStyle(.bordered)
                .disabled(gmailQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isWorking)
            }
            ForEach(coordinator.gmailMessages.prefix(6)) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.subject.isEmpty ? "No subject" : message.subject)
                        .font(.caption.weight(.semibold))
                    Text(message.sender)
                        .font(.caption2)
                    Text(message.snippet)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Divider()
            Text("Create a draft (never sends mail)")
                .font(.caption.weight(.semibold))
            TextField("Recipient", text: $draftTo)
                .textFieldStyle(.roundedBorder)
            TextField("CC recipients (comma-separated)", text: $draftCC)
                .textFieldStyle(.roundedBorder)
            TextField("BCC recipients (comma-separated)", text: $draftBCC)
                .textFieldStyle(.roundedBorder)
            TextField("Subject", text: $draftSubject)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $draftBody)
                .frame(minHeight: 60)
                .padding(5)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button("Review draft") {
                _ = coordinator.proposeGmailDraft(
                    BrowserGmailDraftContent(
                        to: recipientList(draftTo),
                        cc: recipientList(draftCC),
                        bcc: recipientList(draftBCC),
                        subject: draftSubject,
                        body: draftBody
                    )
                )
            }
            .buttonStyle(.bordered)
            .disabled(
                draftTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draftSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    @ViewBuilder
    private func calendarActions(_ profile: BrowserConnectorProfile) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button("Load next 7 days") {
                Task {
                    await coordinator.loadCalendar(
                        from: Date(),
                        to: Date().addingTimeInterval(7 * 24 * 3_600)
                    )
                }
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.isWorking)
            ForEach(coordinator.calendarEvents.prefix(6)) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                    Text(event.start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Create an event after exact approval")
                .font(.caption.weight(.semibold))
            TextField("Calendar ID", text: $eventCalendarID)
                .textFieldStyle(.roundedBorder)
            TextField("Event title", text: $eventTitle)
                .textFieldStyle(.roundedBorder)
            DatePicker("Start", selection: $eventStart)
            DatePicker("End", selection: $eventEnd, in: eventStart...)
            TextField("IANA time zone", text: $eventTimeZone)
                .textFieldStyle(.roundedBorder)
            TextField("Location (optional)", text: $eventLocation)
                .textFieldStyle(.roundedBorder)
            Text("Notes (optional)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextEditor(text: $eventNotes)
                .frame(minHeight: 60)
                .padding(5)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button("Review event") {
                _ = coordinator.proposeCalendarEvent(
                    BrowserCalendarEventProposalContent(
                        calendarID: eventCalendarID,
                        title: eventTitle,
                        start: eventStart,
                        end: eventEnd,
                        timeZoneIdentifier: eventTimeZone,
                        location: optionalField(eventLocation),
                        notes: optionalField(eventNotes)
                    )
                )
            }
            .buttonStyle(.bordered)
            .disabled(
                eventCalendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || eventTimeZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || eventEnd <= eventStart
            )
        }
    }

    @ViewBuilder
    private func mutationReview(_ proposal: BrowserConnectorMutationProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(proposalStatusTitle(proposal.status), systemImage: proposalStatusIcon(proposal.status))
                .font(.subheadline.weight(.semibold))
            switch proposal.payload {
            case .gmailDraft(let draft):
                exactPreviewField("To", value: draft.to.joined(separator: ", "))
                exactPreviewField("CC", value: draft.cc.isEmpty ? "None" : draft.cc.joined(separator: ", "))
                exactPreviewField("BCC", value: draft.bcc.isEmpty ? "None" : draft.bcc.joined(separator: ", "))
                exactPreviewField("Subject", value: draft.subject)
                Text("Body")
                    .font(.caption.weight(.semibold))
                ScrollView {
                    Text(draft.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
                .padding(7)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            case .calendarEvent(let event):
                exactPreviewField("Calendar ID", value: event.calendarID)
                exactPreviewField("Title", value: event.title)
                exactPreviewField("Start", value: exactDate(event.start))
                exactPreviewField("End", value: exactDate(event.end))
                exactPreviewField("Time zone", value: event.timeZoneIdentifier)
                exactPreviewField("Location", value: event.location ?? "None")
                Text("Notes")
                    .font(.caption.weight(.semibold))
                ScrollView {
                    Text(event.notes ?? "None")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(7)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text("Committed payload: \(proposal.payloadCommitment)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if proposal.status == .requiresApproval {
                HStack {
                    Button("Approve once") {
                        Task { await coordinator.approveAndExecuteMutation(proposal.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.isWorking)
                    Button("Deny") {
                        coordinator.denyMutation(proposal.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.isWorking)
                }
            } else if proposal.status == .executing {
                ProgressView("Executing once…")
                    .controlSize(.small)
            }
        }
        .font(.caption)
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("connector-mutation-proposal")
    }

    private func beginAuthorization(_ kind: BrowserConnectorKind) {
        do {
            let url = try coordinator.beginAuthorization(for: kind)
            localError = nil
            openURL(url)
        } catch {
            localError = error.localizedDescription
        }
    }

    private func scopeSummary(_ kind: BrowserConnectorKind) -> String {
        switch kind {
        case .gmail:
            "Scopes: Gmail read-only + compose drafts. Sending mail is not implemented."
        case .googleCalendar:
            "Scopes: Calendar read-only + event creation. Every write is proposed first."
        }
    }

    @ViewBuilder
    private func exactPreviewField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption.weight(.semibold))
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func recipientList(_ value: String) -> [String] {
        value.split(separator: ",", omittingEmptySubsequences: true).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func optionalField(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func exactDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func proposalStatusTitle(_ status: BrowserConnectorProposalStatus) -> String {
        switch status {
        case .requiresApproval: "Approval required"
        case .approved: "Approved"
        case .executing: "Executing once"
        case .completed: "Completed"
        case .ambiguousFailed: "Outcome unconfirmed — not retried"
        case .denied: "Denied"
        case .expired: "Expired"
        }
    }

    private func proposalStatusIcon(_ status: BrowserConnectorProposalStatus) -> String {
        switch status {
        case .requiresApproval: "exclamationmark.shield"
        case .approved: "checkmark.shield"
        case .executing: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .ambiguousFailed: "questionmark.diamond"
        case .denied: "xmark.shield"
        case .expired: "clock.badge.exclamationmark"
        }
    }
}
