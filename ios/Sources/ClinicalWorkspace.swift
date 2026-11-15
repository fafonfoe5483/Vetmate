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
                Section("Clinical records") {
                    ForEach(store.cases) { c in
                        NavigationLink { CaseWorkspace(store: store, id: c.id) } label: {
                            Label(c.name, systemImage: c.species == "Dog" ? "dog" : "cat")
                        }
                    }.onDelete { offsets in
                        var next = store.cases
                        next.remove(atOffsets: offsets); store.save(next)
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
    @State private var due = Date()
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
                    DatePicker("Due", selection: $due)
                    Button("Add task") {
                        let t = ClinicalTask(title: task, due: due)
                        store.change(id) { $0.tasks.append(t) }; task = ""
                    }.disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(c.tasks.sorted { $0.due < $1.due }) { t in
                        Button {
                            store.change(id) { item in
                                if let i = item.tasks.firstIndex(where: { $0.id == t.id }) {
                                    item.tasks[i].completed = item.tasks[i].completed == nil ? Date() : nil
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: t.completed == nil ? "circle" : "checkmark.circle.fill")
                                VStack(alignment: .leading) {
                                    Text(t.title)
                                    Text(t.due.formatted()).font(.caption)
                                    if let done = t.completed { Text("Checked " + done.formatted()).font(.caption) }
                                }
                            }
                        }
                    }
                    Text("Checklist only; no background alarms. Record actual administration separately in Vetspire.").font(.caption).foregroundStyle(.secondary)
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
    var result: Double? {
        guard let w = Double(weight), let d = Double(dose), let c = Double(concentration), w > 0, d > 0, c > 0 else { return nil }
        let v = w*d/c
        return v.isFinite && v > 0 ? v : nil
    }
    var body: some View {
        Form {
            Text("Only use a veterinarian-prescribed dose and verified label concentration. This is arithmetic, not a safe-dose check.").foregroundStyle(.orange)
            TextField("Weight (kg)", text: $weight).keyboardType(.decimalPad)
            TextField("Ordered dose (mg/kg)", text: $dose).keyboardType(.decimalPad)
            TextField("Concentration (mg/mL)", text: $concentration).keyboardType(.decimalPad)
            TextField("Independently calculated volume (mL)", text: $expected).keyboardType(.decimalPad)
            if let v = result {
                Text("Calculated: " + v.formatted(.number.precision(.significantDigits(1...8))) + " mL").font(.title2.bold())
                if let e = Double(expected), e.isFinite, e > 0 {
                    Text("Absolute difference: " + abs(e-v).formatted(.number.precision(.significantDigits(1...8))) + " mL")
                }
                Text("No automatic rounding or clinical approval. Verify syringe precision and order with the veterinary team.")
            }
        }.navigationTitle("Dose Check")
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
