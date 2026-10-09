import SwiftUI

struct LowPowerModeControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var lowPower = model.lowPowerMode
        HStack {
            Toggle("Low Power Mode", isOn: Binding(
                get: { lowPower.isEnabled ?? false },
                set: { lowPower.setEnabled($0) }
            ))
            .disabled(lowPower.isEnabled == nil || lowPower.isChanging)
            .accessibilityValue(Text(LocalizedStringKey(lowPower.isEnabled.map { $0 ? "On" : "Off" } ?? "n/a")))
            if lowPower.isChanging {
                ProgressView().controlSize(.small)
            } else if lowPower.isEnabled == nil {
                Text("n/a").foregroundStyle(.secondary)
            }
        }
        .task { await lowPower.refresh() }
        .alert("Low Power Mode", isPresented: Binding(
            get: { lowPower.errorMessageKey != nil },
            set: { if !$0 { lowPower.errorMessageKey = nil } }
        )) {
            Button("OK", role: .cancel) { lowPower.errorMessageKey = nil }
        } message: {
            Text(LocalizedStringKey(lowPower.errorMessageKey ?? ""))
        }
    }
}
