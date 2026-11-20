import Charts
import CloudKit
import SwiftUI

/// Friends tab: your week next to the friends who share with you.
struct FriendsView: View {
    @Environment(WaterModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(FriendsModel.self) private var friends

    @State private var week: Week = .this
    @State private var managingShare = false
    @State private var confirmingStop = false

    enum Week: Int, CaseIterable, Identifiable {
        case this = 0
        case last = 1

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .this: "This week"
            case .last: "Last week"
            }
        }
    }

    private var comparison: WeeklyComparison {
        let me = Participant.me(friends.mySummary(history: model.history, goal: settings.dailyGoal))
        return WeeklyComparison(participants: [me] + friends.friends, weeksAgo: week.rawValue)
    }

    var body: some View {
        @Bindable var friends = friends

        NavigationStack {
            List {
                if !friends.accountAvailable {
                    Section {
                        ContentUnavailableView(
                            "Sign in to iCloud",
                            systemImage: "icloud.slash",
                            description: Text("Friends uses your own iCloud to share. Sign in to iCloud in the Settings app to use it.")
                        )
                    }
                } else if !friends.isSharing && friends.friends.isEmpty {
                    welcome
                } else {
                    comparisonSections
                }

                if friends.accountAvailable {
                    sharingSection
                }
            }
            .themedBackground()
            .navigationTitle("Friends")
            .refreshable { await friends.refresh() }
            .task { await friends.refresh() }
            .sheet(isPresented: $managingShare) {
                if let share = friends.share {
                    ManageSharingView(share: share, container: friends.container)
                        .ignoresSafeArea()
                }
            }
            .confirmationDialog("Stop sharing?", isPresented: $confirmingStop, titleVisibility: .visible) {
                Button("Stop sharing", role: .destructive) {
                    Task { await friends.stopSharing() }
                }
            } message: {
                Text("Your summary will be deleted from iCloud and your friends will no longer see you. You will still see friends who share with you.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { friends.errorMessage != nil },
                set: { if !$0 { friends.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(friends.errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var welcome: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Compare your week with friends")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("Invite friends who also use the app. You will see each other's water per day and how close everyone gets to their own goal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Start sharing") {
                    Task { await friends.startSharing() }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } footer: {
            Text("Only your name, your daily goal and how much you drank each day of the last four weeks are shared, and only with people you invite.")
        }
    }

    @ViewBuilder
    private var comparisonSections: some View {
        let unit = settings.unit
        let comparison = comparison

        Section {
            Picker("Week", selection: $week) {
                ForEach(Week.allCases) { week in
                    Text(week.title).tag(week)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        Section {
            Chart {
                ForEach(comparison.standings) { standing in
                    let name = standing.participant.summary.name
                    ForEach(standing.days) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Amount", unit.value(fromMilliliters: day.milliliters))
                        )
                        .foregroundStyle(by: .value("Person", name))
                        .position(by: .value("Person", name))
                        .cornerRadius(3)
                    }
                }
            }
            .chartXScale(domain: comparison.weekStart...(Calendar.current.date(byAdding: .day, value: 7, to: comparison.weekStart) ?? comparison.weekStart))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: 220)
            .padding(.vertical, 8)
            .accessibilityLabel(Text("Water per day for each person"))
        }

        Section {
            ForEach(Array(comparison.standings.enumerated()), id: \.element.id) { index, standing in
                StandingRow(rank: index + 1, standing: standing, unit: unit, daysInWeek: comparison.days.count)
                    .swipeActions {
                        if !standing.participant.isMe {
                            Button("Remove", role: .destructive) {
                                Task { await friends.remove(standing.participant) }
                            }
                        }
                    }
            }
        } header: {
            Text("Ranking")
        } footer: {
            Text("Ranked by how close each person got to their own daily goal, so different goals compare fairly.")
        }

        if friends.friends.isEmpty {
            Section {
                Text("No friends yet. Invite someone below; once they accept and invite you back, they appear here.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sharingSection: some View {
        @Bindable var friends = friends
        if friends.isSharing {
            Section {
                TextField("Your name", text: $friends.displayName)
                    .textContentType(.givenName)
                ShareLink(
                    item: FriendInvite(),
                    preview: SharePreview(Text(verbatim: "Water Tracker KC"), image: Image(systemName: "drop.fill"))
                ) {
                    Label("Invite a friend", systemImage: "person.badge.plus")
                }
                if friends.share != nil {
                    Button {
                        managingShare = true
                    } label: {
                        Label("Manage who sees my water", systemImage: "person.2.badge.gearshape")
                    }
                }
                Button("Stop sharing", role: .destructive) {
                    confirmingStop = true
                }
            } header: {
                Text("My sharing")
            } footer: {
                Text("Friends see your name, goal and daily totals, read-only. It is stored in your own iCloud and shared through Apple; this app has no servers. Your friends also need the app.")
            }
        }
    }
}

/// One line of the ranking.
private struct StandingRow: View {
    let rank: Int
    let standing: WeekStanding
    let unit: VolumeUnit
    let daysInWeek: Int

    var body: some View {
        let summary = standing.participant.summary
        HStack(spacing: 12) {
            Text(rank, format: .number)
                .font(Theme.number(24))
                .foregroundStyle(rank == 1 ? Theme.gold : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(standing.participant.isMe ? String(localized: "\(summary.name) (you)") : summary.name)
                        .font(.body.weight(standing.participant.isMe ? .semibold : .regular))
                    Spacer()
                    Text(standing.goalRatio, format: .percent.precision(.fractionLength(0)))
                        .font(Theme.number(22))
                        .foregroundStyle(standing.goalRatio >= 1 ? Theme.good : Color.primary)
                }
                ProgressView(value: min(standing.goalRatio, 1))
                    .tint(standing.goalRatio >= 1 ? Theme.good : Color.accentColor)
                HStack {
                    Text("\(unit.format(standing.total)) total")
                    Spacer()
                    Text("Goal met \(standing.daysGoalMet) of \(daysInWeek) days")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !standing.participant.isMe {
                    Text("Updated \(summary.updatedAt, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// What the invite button shares: an iCloud invitation to read your summary.
/// Recipients can only read, and only the people you pick can open it.
nonisolated struct FriendInvite: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { _ in
            .prepareShare(
                container: FriendsCloud.shared.container,
                allowedSharingOptions: CKAllowedSharingOptions(
                    allowedParticipantPermissionOptions: .readOnly,
                    allowedParticipantAccessOptions: .specifiedRecipientsOnly
                )
            ) {
                let name = UserDefaults.standard.string(forKey: "friendsDisplayName")?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = name.isEmpty ? "Water Tracker KC" : String(localized: "\(name)'s water")
                return try await FriendsCloud.shared.makeShare(title: title)
            }
        }
    }
}

/// Apple's screen for seeing and removing the people you invited.
private struct ManageSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadOnly, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}

#Preview {
    FriendsView()
        .environment(AppSettings.shared)
        .environment(WaterModel.shared)
        .environment(FriendsModel.shared)
}
