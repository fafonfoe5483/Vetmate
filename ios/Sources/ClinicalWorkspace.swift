import SwiftUI
import PhotosUI
import Vision
import Charts
import PDFKit
import CoreText
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct ClinicalEntry: Codable, Identifiable {
    var id = UUID()
    var time = Date()
    var kind: String
    var body: String
    var heartRate: Double? = nil
}
struct ClinicalTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var due: Date
    var notificationRequested: Bool? = nil
    var completed: Date? = nil
}
struct ClinicalCase: Codable, Identifiable {
    var id = UUID()
    var name: String
    var species: String
    var entries: [ClinicalEntry] = []
    var tasks: [ClinicalTask] = []
}
@MainActor final class ClinicalStore: ObservableObject {
    @Published var cases: [ClinicalCase] = []
    @Published var error: String?
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VetMateClinicalBeta.json")
    init() {
        if FileManager.default.fileExists(atPath: url.path) {
            do { cases = try JSONDecoder().decode([ClinicalCase].self, from: Data(contentsOf: url)) }
            catch { self.error = "Unable to read saved records. Changes are disabled to protect existing data." }
        }
    }
    func save(_ next: [ClinicalCase]) {
        guard error == nil else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtection])
            var target = url
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try target.setResourceValues(values)
            cases = next
        } catch { self.error = "Unable to save protected records. Reopen the app before trying again." }
    }
    func change(_ id: UUID, _ edit: (inout ClinicalCase) -> Void) {
        var next = cases
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        edit(&next[i]); save(next)
    }
}
struct ClinicalWorkspace: View {
    @StateObject private var store = ClinicalStore()
    @State private var name = ""
    @State private var species = "Dog"
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Private beta • fictional patients only. Documentation aid, not a monitor or prescribing tool.").foregroundStyle(.orange)
                    if let error = store.error { Text(error).foregroundStyle(.red) }
                }
                Section("New working record") {
                    TextField("Patient name / test identifier", text: $name)
                    Picker("Species", selection: $species) { Text("Dog").tag("Dog"); Text("Cat").tag("Cat") }
                    Button("Create record") {
                        store.save(store.cases + [ClinicalCase(name: name.trimmingCharacters(in: .whitespacesAndNewlines), species: species)])
                        name = ""
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.error != nil)
                }
                Section("All patient reminders") {
                    NavigationLink { AllPatientReminders(store: store) } label: { Label("Upcoming & overdue", systemImage: "bell.badge") }
                }
                Section("Clinical records") {
                    ForEach(store.cases) { c in
                        NavigationLink { CaseWorkspace(store: store, id: c.id) } label: {
                            Label(c.name, systemImage: c.species == "Dog" ? "dog" : "cat")
                        }
                    }.onDelete { offsets in
                        var next = store.cases
                        let removed = offsets.flatMap { next[$0].tasks.map { PatientNotification.key($0.id) } }
                        next.remove(atOffsets: offsets); store.save(next)
                        if store.error == nil { PatientNotification.cancel(removed) }
                    }
                }
                Section("Quick tools") {
                    NavigationLink("Independent dose arithmetic check") { DoseCheck() }
                    NavigationLink("CPR practice timer") { PracticeTimer() }
                    NavigationLink("Clinical reference") { ClinicalReferences() }
                    NavigationLink("Vetspire & monitor integration") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Not connected").font(.title.bold())
                            Text("Clinic approval, restricted API access and a secure backend are required before connecting Vetspire. A supported monitor model and manufacturer interface are required for device data.")
                            Text("For now, use reviewed note exports. Never paste API credentials into this app.")
                            Link("Vetspire", destination: URL(string: "https://vetspire.com/")!)
                        }.padding()
                    }
                }
            }.navigationTitle("Clinical Tools")
        }
    }
}
struct CaseWorkspace: View {
    @ObservedObject var store: ClinicalStore
    let id: UUID
    @State private var task = ""
    @State private var due = Date().addingTimeInterval(900)
    @State private var timeMode = "Countdown"
    @State private var minutes = 15
    @State private var notify = true
    @State private var notificationStatus = ""
    @State private var scheduling = false
    @State private var note = ""
    @State private var pdf: URL?
    @State private var reportError = ""
    private var record: ClinicalCase? { store.cases.first { $0.id == id } }
    var body: some View {
        List {
            if let c = record {
                Section("Capture") {
                    NavigationLink("Vital signs / anesthesia log") { VitalEntry { entry in store.change(id) { $0.entries.append(entry) } } }
                    NavigationLink("Scan lab report or monitor display") { ClinicalScan { entry in store.change(id) { $0.entries.append(entry) } } }
                    TextField("Note (keyboard dictation supported)", text: $note, axis: .vertical)
                    Button("Save note") {
                        store.change(id) { $0.entries.append(ClinicalEntry(kind: "Note", body: note)) }; note = ""
                    }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Treatment checklist") {
                    TextField("Task from veterinarian's order", text: $task)
                    Picker("Reminder type", selection: $timeMode) {
                        Text("Countdown").tag("Countdown")
                        Text("Exact date / time").tag("Exact")
                    }.pickerStyle(.segmented)
                    if timeMode == "Countdown" {
                        Picker("Check in", selection: $minutes) {
                            ForEach([5,10,15,20,30,45,60,90,120,180,240], id: \.self) { m in Text("\(m) min").tag(m) }
                        }
                        Stepper("Custom: \(minutes) min", value: $minutes, in: 1...1440)
                    } else { DatePicker("Due", selection: $due, in: Date()...) }
                    Toggle("iPhone notification", isOn: $notify)
                    Button(scheduling ? "Scheduling…" : "Add patient reminder") {
                        let deadline = timeMode == "Countdown" ? Date().addingTimeInterval(Double(minutes)*60) : due
                        guard deadline.timeIntervalSinceNow > 1 else { notificationStatus = "Choose a future time."; return }
                        let t = ClinicalTask(title: task.trimmingCharacters(in: .whitespacesAndNewlines), due: deadline, notificationRequested: notify)
                        store.change(id) { $0.tasks.append(t) }
                        guard store.error == nil else { notificationStatus = "Not saved."; return }
                        task = ""
                        if notify {
                            scheduling = true
                            Task {
                                notificationStatus = await PatientNotification.schedule(t, patient: c.name)
                                scheduling = false
                            }
                        } else { notificationStatus = "Saved to checklist only." }
                    }.disabled(scheduling || store.error != nil || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !notificationStatus.isEmpty { Text(notificationStatus).font(.caption).foregroundStyle(.orange) }
                    ForEach(c.tasks.sorted { $0.due < $1.due }) { t in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(t.title).bold()
                                Text(t.due.formatted()).font(.caption)
                                if let done = t.completed { Text("Completed " + done.formatted()).font(.caption) }
                                else if t.due <= Date() { Text("Due / overdue").foregroundStyle(.orange).font(.caption) }
                                else { Text(t.notificationRequested == true ? "Notification requested" : "Checklist only").font(.caption) }
                            }
                            Spacer()
                            if t.completed == nil {
                                Button("Done") {
                                    store.change(id) { item in
                                        if let i = item.tasks.firstIndex(where: { $0.id == t.id }) { item.tasks[i].completed = Date() }
                                    }
                                    if store.error == nil { PatientNotification.cancel([PatientNotification.key(t.id)]) }
                                }.buttonStyle(.borderless)
                            }
                            Button(role: .destructive) {
                                store.change(id) { $0.tasks.removeAll { $0.id == t.id } }
                                if store.error == nil { PatientNotification.cancel([PatientNotification.key(t.id)]) }
                            } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }.swipeActions {
                            if t.completed == nil && t.due > Date() && t.notificationRequested == true {
                                Button("Retry alert") {
                                    scheduling = true
                                    Task { notificationStatus = await PatientNotification.schedule(t, patient: c.name); scheduling = false }
                                }.tint(.blue)
                            }
                        }
                    }
                    Text("Supplemental reminders only. Notifications can be silenced, delayed or disabled by iOS. Patient name / task may appear on the lock screen; use fictional or clinic-approved identifiers. Follow clinic monitoring and medication schedules independently.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Heart rate trend • entered readings") {
                    let values = c.entries.filter { $0.heartRate != nil }.sorted { $0.time < $1.time }
                    if values.isEmpty { Text("No confirmed readings") }
                    else {
                        Chart(values) { v in
                            LineMark(x: .value("Time", v.time), y: .value("bpm", v.heartRate ?? 0))
                            PointMark(x: .value("Time", v.time), y: .value("bpm", v.heartRate ?? 0))
                        }.frame(height: 160)
                    }
                }
                Section("Timeline") {
                    ForEach(c.entries.reversed()) { e in
                        VStack(alignment: .leading) {
                            Text(e.kind).bold(); Text(e.time.formatted()).font(.caption); Text(e.body)
                        }
                    }
                }
                Section("Handover / export") {
                    ShareLink(item: summary(c)) { Label("Share reviewed text", systemImage: "square.and.arrow.up") }
                    Button("Prepare PDF draft") {
                        do { pdf = try makePDF(summary(c)); reportError = "" }
                        catch { reportError = "Could not prepare PDF." }
                    }
                    if let pdf { ShareLink(item: pdf) { Label("Share PDF draft", systemImage: "doc") } }
                    if !reportError.isEmpty { Text(reportError) }
                    Text("Manual transfer only. Verify content and patient identity in Vetspire.").font(.caption)
                }
            }
        }.navigationTitle(record?.name ?? "Record")
    }
    func summary(_ c: ClinicalCase) -> String {
        var out = ["VetMate beta • unverified clinical draft", c.name + " • " + c.species, "Generated " + Date().formatted()]
        out += c.entries.sorted { $0.time < $1.time }.map { $0.time.formatted() + " | " + $0.kind + "\n" + $0.body }
        out += c.tasks.map { $0.due.formatted() + " | " + $0.title + " | " + ($0.completed?.formatted() ?? "Pending") }
        return out.joined(separator: "\n\n")
    }
    func makePDF(_ text: String) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let attr = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black])
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VetMate-" + UUID().uuidString + ".pdf")
        try renderer.writePDF(to: url) { ctx in
            var offset = 0
            while offset < attr.length {
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.saveGState(); cg.translateBy(x: 0, y: 792); cg.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: 40, y: 40, width: 532, height: 712), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                CTFrameDraw(frame, cg); cg.restoreGState()
                let n = CTFrameGetVisibleStringRange(frame).length
                if n <= 0 { break }; offset += n
            }
        }
        return url
    }
}
struct VitalEntry: View {
    @Environment(\.dismiss) private var dismiss
    let save: (ClinicalEntry) -> Void
    @State private var when = Date()
    @State private var readings = Array(repeating: "", count: 8)
    @State private var confirmed = false
    let labels = ["Heart rate (bpm)", "Respiratory rate (/min)", "SpO₂ (%)", "ETCO₂ (mmHg)", "Systolic BP (mmHg)", "Diastolic BP (mmHg)", "MAP (mmHg)", "Temperature (°F)"]
    private var valid: Bool {
        let parsed = readings.enumerated().filter { !$0.element.isEmpty }
        return !parsed.isEmpty && parsed.allSatisfy { item in
            guard let n = Double(item.element), n.isFinite, n >= 0 else { return false }
            return item.offset != 2 || n <= 100
        }
    }
    var body: some View {
        Form {
            Text("Manual transcription only. Check the actual monitor and use its alarms. Blank means not measured.").foregroundStyle(.orange)
            DatePicker("Observation time", selection: $when)
            ForEach(labels.indices, id: \.self) { i in
                TextField(labels[i], text: $readings[i]).keyboardType(.decimalPad)
            }
            Toggle("I verified values, units and time", isOn: $confirmed)
            Button("Save observation") {
                let body = labels.indices.filter { !readings[$0].isEmpty }.map { labels[$0] + ": " + readings[$0] }.joined(separator: "\n")
                save(ClinicalEntry(time: when, kind: "Manual vitals", body: body, heartRate: Double(readings[0]))); dismiss()
            }.disabled(!valid || !confirmed)
        }.navigationTitle("Vitals").onChange(of: readings) { _,_ in confirmed = false }.onChange(of: when) { _,_ in confirmed = false }
    }
}
struct ClinicalScan: View {
    @Environment(\.dismiss) private var dismiss
    let save: (ClinicalEntry) -> Void
    @State private var image: PhotosPickerItem?
    @State private var camera = false
    @State private var text = ""
    @State private var kind = "Lab report"
    @State private var confirmed = false
    @State private var status = "Choose a clear image without client identifiers."
    @State private var busy = false
    var body: some View {
        Form {
            Picker("Source", selection: $kind) { Text("Lab report").tag("Lab report"); Text("Monitor snapshot").tag("Monitor snapshot") }
            Button("Take photo") { camera = true }.disabled(busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
            PhotosPicker("Choose photo", selection: $image, matching: .images).disabled(busy)
            Text(status).font(.caption)
            TextEditor(text: $text).frame(minHeight: 200)
            Text("Copy the analyzer's own units, ranges and flags. No automatic diagnosis or monitor alarm interpretation.").font(.caption).foregroundStyle(.orange)
            Toggle("I verified transcription against the source", isOn: $confirmed)
            Button("Save reviewed text") { save(ClinicalEntry(kind: kind + " • reviewed transcription", body: text)); dismiss() }.disabled(!confirmed || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
        }.navigationTitle("Clinical Scan")
        .sheet(isPresented: $camera) { Camera { data in if let data { scan(data) } } }
        .onChange(of: image) { _, new in
            guard let new else { return }; busy = true; confirmed = false; text = ""
            Task { if let data = try? await new.loadTransferable(type: Data.self) { scan(data) } else { busy = false; status = "Unable to load image." } }
        }
        .onChange(of: text) { _,_ in confirmed = false }
        .onChange(of: kind) { _,_ in confirmed = false }
    }
    func scan(_ data: Data) {
        busy = true; confirmed = false; text = ""; status = "Reading image locally…"
        Task {
            let result = await Task.detached { () -> String in
                let r = VNRecognizeTextRequest(); r.recognitionLevel = .accurate; r.usesLanguageCorrection = false
                do { try VNImageRequestHandler(data: data, options: [:]).perform([r]); return (r.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") }
                catch { return "" }
            }.value
            text = result; busy = false; status = result.isEmpty ? "No readable text. Retake or enter manually." : "Review every value, decimal, label and unit."
        }
    }
}
struct DoseCheck: View {
    @State private var weight = ""
    @State private var dose = ""
    @State private var concentration = ""
    @State private var expected = ""

    private var result: Double? {
        guard let w = Double(weight), let d = Double(dose), let c = Double(concentration),
              w.isFinite, d.isFinite, c.isFinite, w > 0, d > 0, c > 0 else { return nil }
        let v = w * d / c
        return v.isFinite && v > 0 ? v : nil
    }
    private var difference: Double? {
        guard let v = result, let e = Double(expected), e.isFinite, e > 0 else { return nil }
        return abs(e - v)
    }
    private func display(_ value: Double) -> String {
        String(format: "%.8g", value)
    }
    private var inputs: some View {
        Section("Verified prescription and label") {
            TextField("Weight (kg)", text: $weight).keyboardType(.decimalPad)
            TextField("Ordered dose (mg/kg)", text: $dose).keyboardType(.decimalPad)
            TextField("Concentration (mg/mL)", text: $concentration).keyboardType(.decimalPad)
            TextField("Independently calculated volume (mL)", text: $expected).keyboardType(.decimalPad)
        }
    }
    @ViewBuilder private var output: some View {
        if let v = result {
            Section("Arithmetic result") {
                Text("Calculated: " + display(v) + " mL").font(.title2.bold())
                if let delta = difference {
                    Text("Absolute difference: " + display(delta) + " mL")
                }
                Text("No automatic rounding or clinical approval. Verify syringe precision and order with the veterinary team.")
            }
        }
    }
    var body: some View {
        Form {
            Text("Only use a veterinarian-prescribed dose and verified label concentration. This is arithmetic, not a safe-dose check.").foregroundStyle(.orange)
            inputs
            output
            Section("Actual formula used") {
                Text("Volume (mL) = weight (kg) × dose (mg/kg) ÷ concentration (mg/mL)")
            }
        }
        .navigationTitle("Dose Check")
    }
}
struct PracticeTimer: View {
    @State private var end: Date?
    var body: some View {
        VStack(spacing: 20) {
            Text("CPR training timer").font(.title.bold())
            Text("Practice only. Not an emergency alarm or treatment protocol. Follow clinic RECOVER training.")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = end.map { max(0, Int(ceil($0.timeIntervalSince(context.date)))) } ?? 120
                Text(String(format: "%02d:%02d", seconds/60, seconds%60)).font(.system(size: 64, weight: .bold, design: .monospaced))
            }
            Button("Start / restart 2-minute practice cycle") { end = Date().addingTimeInterval(120) }.buttonStyle(.borderedProminent)
            Button("Reset") { end = nil }
            Text("No audible alerts or background guarantee.").font(.caption)
        }.padding().navigationTitle("Practice")
    }
}
struct ClinicalReferences: View {
    var body: some View {
        List {
            Link("RECOVER CPR initiative", destination: URL(string: "https://recoverinitiative.org/")!)
            Link("AAHA guidelines", destination: URL(string: "https://www.aaha.org/")!)
            Link("DailyMed drug labeling", destination: URL(string: "https://dailymed.nlm.nih.gov/")!)
            Link("FDA animal drugs", destination: URL(string: "https://animaldrugsatfda.fda.gov/adafda/views/#/search")!)
            Link("WSAVA global guidelines", destination: URL(string: "https://wsava.org/global-guidelines/")!)
            Text("Links are reference starting points, not a comprehensive validated clinical library.")
        }.navigationTitle("References")
    }
}

enum PatientNotification {
    static func key(_ id: UUID) -> String { "vetmate.patient." + id.uuidString }
    static func cancel(_ ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
    static func schedule(_ task: ClinicalTask, patient: String) async -> String {
        let center = UNUserNotificationCenter.current()
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard allowed else { return "Saved, but notifications are OFF. Enable VetMate notifications in iPhone Settings." }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return "Saved, but notification permission is unavailable." }
            let seconds = task.due.timeIntervalSinceNow
            guard seconds > 0 else { return "Reminder is already due. Check the patient task list." }
            let pending = await center.pendingNotificationRequests()
            guard pending.contains(where: { $0.identifier == key(task.id) }) || pending.count < 60 else { return "Saved, but too many pending iPhone alerts. Complete or delete reminders before retrying." }
            let content = UNMutableNotificationContent()
            content.title = "VetMate • " + patient
            content.body = task.title
            content.sound = .default
            let request = UNNotificationRequest(identifier: key(task.id), content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
            try await center.add(request)
            return settings.soundSetting == .enabled && settings.alertSetting == .enabled ? "iPhone reminder scheduled. Verify notification settings and test before use." : "Reminder scheduled, but iPhone sounds or banners may be disabled."
        } catch { return "Saved, but the iPhone reminder could not be scheduled. Retry from the task list." }
    }
}
struct AllPatientReminders: View {
    @ObservedObject var store: ClinicalStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            List {
                ForEach(store.cases.flatMap { c in c.tasks.filter { $0.completed == nil }.map { ReminderRow(patient: c, task: $0) } }.sorted { $0.task.due < $1.task.due }) { row in
                    NavigationLink { CaseWorkspace(store: store, id: row.patient.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.patient.name).font(.headline)
                            Text(row.task.title)
                            Text(row.task.due.formatted()).font(.caption)
                            if row.task.due <= context.date { Text("Due / overdue").foregroundStyle(.orange) }
                            else { Text(row.task.due, style: .timer).monospacedDigit().foregroundStyle(.blue) }
                        }
                    }
                }
                Text("Supplemental checklist — keep clinic alarms and monitoring active.").font(.caption)
            }
        }.navigationTitle("Patient Reminders")
    }
    struct ReminderRow: Identifiable {
        var id: UUID { task.id }
        let patient: ClinicalCase
        let task: ClinicalTask
    }
}
