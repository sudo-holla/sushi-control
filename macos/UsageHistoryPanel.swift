import SwiftUI
import Charts

struct UsageHistoryPanel:View {
    @ObservedObject var store:ServerStore
    @ObservedObject var history:UsageHistory
    @State private var days = 7
    @State private var rangeStart = Calendar.current.startOfDay(for:Date().addingTimeInterval(-6*86400))
    @State private var rangeEnd = Date()
    @State private var exportError = ""
    static let retention = 30
    var earliest:Date { Calendar.current.date(byAdding:.day,value:-Self.retention,to:Calendar.current.startOfDay(for:Date())) ?? Date() }
    var windowStart:Date { days == 0 ? max(rangeStart,earliest) : Calendar.current.date(byAdding:.day,value:1-days,to:Calendar.current.startOfDay(for:Date())) ?? Date() }
    var windowEnd:Date { days == 0 ? min(max(rangeEnd,rangeStart),Date()) : Date() }
    var rows:[UsageBucket] { history.rows(endpoint:store.connectedEndpoint,since:windowStart,through:windowEnd) }
    var total:UsageCounts { rows.reduce(into:UsageCounts()) { $0.add($1.counts) } }
    var rangeNote:String {
        let range = windowStart.formatted(date:.abbreviated,time:.omitted)+" – "+windowEnd.formatted(date:.abbreviated,time:.omitted)
        return days == 0 ? "Custom range "+range+". Only the last "+String(Self.retention)+" days of usage are kept on this Mac." : range
    }
    var body:some View {
        SushiCard("Saved usage") {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Toggle("Record usage on this Mac",isOn:$store.usageEnabled).toggleStyle(.switch)
                    Spacer()
                    Button("Export JSON…",systemImage:"square.and.arrow.up") { export() }.disabled(history.buckets.filter{$0.endpoint == store.connectedEndpoint}.isEmpty)
                }
                Text("Server-wide counter changes observed while Sushi Control is running. Keeps 30 days locally; no prompts, responses or API keys. Turning recording off keeps saved history.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Period",selection:$days) { Text("Today").tag(1); Text("7 days").tag(7); Text("30 days").tag(30); Text("Custom").tag(0) }.pickerStyle(.segmented).frame(maxWidth:320)
                    Spacer()
                    Text(store.connectedEndpoint).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if days == 0 {
                    HStack(spacing:16) {
                        DatePicker("From",selection:$rangeStart,in:earliest...Date(),displayedComponents:[.date])
                        DatePicker("To",selection:$rangeEnd,in:max(rangeStart,earliest)...Date(),displayedComponents:[.date])
                        Spacer(minLength:24)
                    }.font(.caption)
                }
                Text(rangeNote).font(.caption).foregroundStyle(.secondary)
                if rows.isEmpty {
                    ContentUnavailableView(days == 0 ? "No saved usage in this range" : store.usageEnabled ? "Waiting for new usage" : "No saved usage",systemImage:"chart.bar.xaxis",description:Text(store.usageEnabled ? "New counter changes appear after two consecutive metrics samples." : "Enable recording to collect usage while this app is open."))
                } else {
                    HStack(spacing:24) {
                        summary("Generated",total.generated)
                        summary("Prompt work",total.prefill)
                        summary("Cached",total.cached)
                        summary("Successful requests",total.requests)
                    }
                    Chart(rows) { row in
                        BarMark(x:.value("Hour",row.hour,unit:.hour),y:.value("Generated tokens",row.counts.generated)).foregroundStyle(Color.sushiAccent)
                    }.frame(height:160).chartYAxisLabel("Generated tokens").accessibilityLabel("Observed generated tokens by hour")
                    Text("Counts are assigned to the hour they were sampled. Counter resets, disconnected periods and gaps over 30 seconds start a fresh baseline. This is sampled activity, not a complete billing or server audit log.").font(.caption).foregroundStyle(.secondary)
                }
                if !history.error.isEmpty { Feedback(text:history.error,failure:true) }
                if !exportError.isEmpty { Feedback(text:exportError,failure:true) }
            }.padding(12)
        }
    }
    func summary(_ label:String,_ value:Double)->some View {
        VStack(alignment:.leading,spacing:4) { Text(value.formatted(.number.precision(.fractionLength(0)))).font(.title3.weight(.semibold)).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading)
    }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "sushi-usage.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try history.export(endpoint:store.connectedEndpoint).write(to:url,options:.atomic); exportError = "" }
        catch { exportError = error.localizedDescription }
    }
}
