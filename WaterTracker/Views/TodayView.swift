import SwiftUI

struct TodayView: View {
    @Environment(WaterModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var showingCustomAmount = false
    @State private var logCount = 0

    var body: some View {
        @Bindable var model = model
        let unit = settings.unit

        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        WaterGauge(
                            progress: model.progress,
                            amount: unit.format(model.todayTotal),
                            caption: String(localized: "of \(unit.format(settings.dailyGoal))")
                        )
                        Text(statusText)
                            .font(.headline)
                            .foregroundStyle(model.remaining > 0 ? Color.secondary : Color.green)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if model.access == .denied || model.access == .unavailable {
                    Section {
                        HealthNotice(access: model.access)
                    }
                }

                Section("Quick add") {
                    HStack(spacing: 12) {
                        ForEach(Array(settings.quickAmounts.enumerated()), id: \.offset) { _, amount in
                            Button {
                                add(amount)
                            } label: {
                                Label(unit.format(amount), systemImage: "plus")
                                    .labelStyle(.titleOnly)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityLabel(Text("Log \(unit.format(amount))"))
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Button("Other amount", systemImage: "slider.horizontal.3") {
                        showingCustomAmount = true
                    }
                }

                Section("Today") {
                    if model.entries.isEmpty {
                        Text("Nothing logged yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.entries) { entry in
                            EntryRow(entry: entry, unit: unit)
                                .swipeActions {
                                    if entry.isOwn {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            Task { await model.delete(entry) }
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        Task { await model.undoLast() }
                    }
                    .disabled(model.lastOwnEntry == nil)
                }
            }
            .refreshable { await model.refresh() }
            .sensoryFeedback(.success, trigger: logCount)
            .sheet(isPresented: $showingCustomAmount) {
                CustomAmountSheet { amount in add(amount) }
                    .presentationDetents([.medium])
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var statusText: String {
        model.remaining > 0
            ? String(localized: "\(settings.unit.format(model.remaining)) to go")
            : String(localized: "Goal reached")
    }

    private func add(_ amount: Double) {
        Task {
            if await model.log(amount) {
                logCount += 1
            }
        }
    }
}

private struct EntryRow: View {
    let entry: WaterEntry
    let unit: VolumeUnit

    var body: some View {
        HStack {
            Image(systemName: "drop.fill")
                .foregroundStyle(.tint)
            Text(unit.format(entry.milliliters))
            if !entry.isOwn {
                Text("Other app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.date, style: .time)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HealthNotice: View {
    let access: HealthAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Health access needed", systemImage: "heart.text.square")
                .font(.headline)
            Text(
                access == .unavailable
                    ? "Apple Health is not available on this device, so water cannot be saved."
                    : "Water is saved in Apple Health. Allow access in Settings > Health > Data Access & Devices."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CustomAmountSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let onLog: (Double) -> Void
    @State private var amount: Double = 0

    var body: some View {
        let unit = settings.unit

        NavigationStack {
            VStack(spacing: 24) {
                Text(unit.format(amount))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Slider(value: $amount, in: unit.amountRange, step: unit.amountStep)
                    .accessibilityLabel(Text("Amount"))
                Button {
                    onLog(amount)
                    dismiss()
                } label: {
                    Text("Log")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(24)
            .navigationTitle("Other amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                amount = settings.quickAmounts.first ?? unit.defaultQuickAmounts[0]
            }
        }
    }
}

#Preview {
    TodayView()
        .environment(AppSettings.shared)
        .environment(WaterModel.shared)
}
