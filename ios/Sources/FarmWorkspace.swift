import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import MessageUI
import AVKit

enum FarmSpecies: String, CaseIterable, Codable, Identifiable {
    case goat = "Goat", horse = "Horse", cow = "Cattle", donkey = "Donkey"
    var id: String { rawValue }
    var symbol: String { switch self { case .goat: return "🐐"; case .horse: return "🐎"; case .cow: return "🐄"; case .donkey: return "🫏" } }
    var topics: [String] {
        switch self {
        case .goat: return ["Parasites / anemia", "Bottle jaw", "Bloat", "Urinary obstruction", "Coccidiosis", "Enterotoxemia", "Caseous lymphadenitis", "Hoof disease", "Mastitis", "Pregnancy toxemia"]
        case .horse: return ["Colic", "Choke", "Laminitis", "Hoof abscess", "Thrush", "Rain rot", "Proud flesh", "Eye injury", "Gastric ulcers", "Heat stress"]
        case .cow: return ["Bloat", "Pinkeye", "Foot rot", "Respiratory disease", "Calf diarrhea", "Mastitis", "Hardware disease", "Calving complications", "Mineral disorders"]
        case .donkey: return ["Reduced appetite / hyperlipemia", "Colic", "Laminitis", "Hoof abscess", "Dental disease", "Parasites", "Skin disease", "Obesity"]
        }
    }
    var reference: URL {
        if self == .horse { return URL(string: "https://aaep.org/horse-owners/")! }
        if self == .donkey { return URL(string: "https://www.thedonkeysanctuary.org.uk/for-owners")! }
        return URL(string: "https://www.merckvetmanual.com/")!
    }
}
struct FarmAnimal: Identifiable, Codable {
    var id = UUID()
    var name: String
    var species: FarmSpecies
    var tag = ""
    var weight = ""
    var notes = ""
    var records: [FarmRecord] = []
}
struct FarmRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var kind: String
    var text: String
}
@MainActor final class FarmStore: ObservableObject {
    @Published private(set) var animals: [FarmAnimal] = []
    @Published var error: String?
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VetMateFarm.json")
    init() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { animals = try JSONDecoder().decode([FarmAnimal].self, from: Data(contentsOf: url)) }
        catch { self.error = "Unable to open farm records. Changes disabled to protect existing data." }
    }
    @discardableResult func save(_ next: [FarmAnimal]) -> Bool {
        guard error == nil else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtection])
            var target = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try target.setResourceValues(values)
            animals = next; return true
        } catch { self.error = "Farm records could not be saved."; return false }
    }
    func addRecord(_ id: UUID, _ record: FarmRecord) -> Bool {
        var next = animals
        guard let i = next.firstIndex(where: { $0.id == id }) else { return false }
        next[i].records.insert(record, at: 0)
        return save(next)
    }
}
struct FarmWorkspace: View {
    @StateObject private var store = FarmStore()
    @AppStorage("farmVetPhone") private var phone = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Farm & Livestock").font(.largeTitle.bold()).foregroundStyle(.blue)
                        Text("From the clinic to the farm.").foregroundStyle(.secondary)
                        Text("Beta • veterinary reference and communication aid, not a diagnostic or prescribing system.").font(.caption)
                    }
                }
                Section("Species reference") {
                    ForEach(FarmSpecies.allCases) { s in
                        NavigationLink { FarmReference(species: s) } label: {
                            HStack { Text(s.symbol).font(.largeTitle); Text(s.rawValue + " Health").font(.headline) }
                        }
                    }
                }
                Section("Health assessment & emergency") {
                    NavigationLink { FarmReport(store: store, initialAnimal: nil, phone: phone) } label: { Label("Photo / video health report", systemImage: "camera.viewfinder") }
                    NavigationLink { FarmEmergency(phone: phone) } label: { Label("Emergency guide", systemImage: "cross.case.fill").foregroundStyle(.red) }
                    NavigationLink { FarmMedicationReference() } label: { Label("Livestock medications", systemImage: "pills") }
                    NavigationLink { FarmMath() } label: { Label("Farm calculations", systemImage: "calculator") }
                }
                Section("My animals") {
                    NavigationLink { FarmNewAnimal(store: store) } label: { Label("Add animal", systemImage: "plus.circle") }
                    ForEach(store.animals) { a in
                        NavigationLink { FarmAnimalDetail(store: store, id: a.id, phone: phone) } label: {
                            VStack(alignment: .leading) { Text(a.species.symbol + " " + a.name).font(.headline); Text(a.tag).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let error = store.error { Text(error).foregroundStyle(.red) }
                }
                Section("Farm veterinarian") {
                    TextField("Phone number", text: $phone).keyboardType(.phonePad)
                    Text("Used as the suggested recipient. Always verify the number before sending.").font(.caption)
                }
            }.navigationTitle("Farm")
        }
    }
}
struct FarmNewAnimal: View {
    @ObservedObject var store: FarmStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var species = FarmSpecies.goat
    @State private var tag = ""
    @State private var weight = ""
    @State private var notes = ""
    var body: some View {
        Form {
            Picker("Species", selection: $species) { ForEach(FarmSpecies.allCases) { Text($0.rawValue).tag($0) } }
            TextField("Animal name", text: $name)
            TextField("Tag / ID", text: $tag)
            TextField("Weight and unit (e.g. 115 lb)", text: $weight)
            TextField("Breed, age, sex, known conditions", text: $notes, axis: .vertical)
            Button("Save animal") {
                if store.save(store.animals + [FarmAnimal(name: name.trimmingCharacters(in: .whitespacesAndNewlines), species: species, tag: tag, weight: weight, notes: notes)]) { dismiss() }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.error != nil)
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("New Farm Animal")
    }
}
struct FarmAnimalDetail: View {
    @ObservedObject var store: FarmStore
    let id: UUID
    let phone: String
    @State private var kind = "Health observation"
    @State private var note = ""
    var body: some View {
        List {
            if let a = store.animals.first(where: { $0.id == id }) {
                Section {
                    Text(a.species.symbol + " " + a.name).font(.title.bold())
                    Text(a.species.rawValue + " • " + a.tag)
                    Text(a.weight)
                    Text(a.notes)
                }
                Section("Health report") {
                    NavigationLink { FarmReport(store: store, initialAnimal: a.id, phone: phone) } label: { Label("Create report for veterinarian", systemImage: "message.fill") }
                }
                Section("Farm record") {
                    Picker("Category", selection: $kind) {
                        ForEach(["Health observation","Vaccination","Medication / withdrawal","Hoof care","Weight / body condition","Fecal test / FAMACHA","Breeding / birth","Quarantine","Feed / inventory"], id: \.self) { Text($0) }
                    }
                    TextField("Record observation or vet-approved schedule", text: $note, axis: .vertical)
                    Button("Save entry") {
                        if store.addRecord(id, FarmRecord(kind: kind, text: note)) { note = "" }
                    }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("History") {
                    ForEach(a.records) { r in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(r.kind).font(.headline)
                            Text(r.date.formatted()).font(.caption)
                            Text(r.text)
                        }
                    }
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Farm Animal")
    }
}
struct FarmReference: View {
    let species: FarmSpecies
    var body: some View {
        List {
            Section {
                Text(species.symbol + " " + species.rawValue + " Health").font(.title.bold())
                Text("Reference index, not a diagnosis or treatment protocol. The same signs can have different causes.").font(.caption)
            }
            Section("Common conditions") {
                ForEach(species.topics, id: \.self) { topic in
                    NavigationLink(topic) {
                        List {
                            Section("What to record") {
                                Text("Onset, appetite, water intake, activity, manure and urine, breathing, temperature if safe, recent feed changes, medications, injuries and affected herd mates.")
                                Text("Ask your veterinarian which physical examination, fecal testing, blood tests, imaging or other diagnostics are appropriate.")
                            }
                            Section("Treatment and procedures") {
                                Text("Confirm the diagnosis, medication, dose, route, duration, monitoring and any food withdrawal interval with your veterinarian. Do not attempt invasive procedures from a reference page.")
                                Link("Veterinary reference", destination: species.reference)
                                Link("Search Merck Veterinary Manual", destination: URL(string: "https://www.merckvetmanual.com/")!)
                            }
                            Section("Urgent signs") { Text("Breathing difficulty, collapse, severe bleeding, inability to urinate, severe abdominal distention or pain, eye injury, inability to stand or difficult birth require prompt veterinary contact.").foregroundStyle(.orange) }
                        }.navigationTitle(topic)
                    }
                }
            }
            Section("Sources") {
                Link("Species veterinary reference", destination: species.reference)
                Link("Texas A&M AgriLife Extension", destination: URL(string: "https://agrilifeextension.tamu.edu/")!)
            }
        }.navigationTitle(species.rawValue)
    }
}
struct FarmEmergency: View {
    let phone: String
    var body: some View {
        List {
            Section {
                Text("Call your veterinarian promptly if any emergency is suspected. Do not wait for a text response.").foregroundStyle(.red).font(.headline)
                if !phone.isEmpty { Link("Call farm veterinarian", destination: URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" })!) }
            }
            Section("Emergency signs") {
                ForEach(["Severe bleeding or deep wound","Breathing difficulty or choke","Severe abdominal pain / distention","Inability to urinate","Eye injury","Collapse or inability to stand","Difficult birth","Suspected poisoning or snakebite","Donkey refusing food"], id: \.self) { Text($0) }
            }
            Section("While arranging care") {
                Text("Keep people safe; avoid restraint if dangerous. Keep the animal quiet if feasible. For external bleeding, apply steady pressure with clean material if safe. Do not probe wounds, remove embedded objects, force food or water, or administer unapproved medicine. Follow the veterinarian's instructions.")
            }
        }.navigationTitle("Emergency Guide")
    }
}
struct FarmMedicationReference: View {
    let drugs = ["Flunixin (Banamine)","Phenylbutazone","Oxytetracycline","Fenbendazole","Ivermectin","Poloxalene","Thiamine","CD&T vaccine","Tetanus antitoxin","Electrolytes"]
    @State private var search = ""
    var body: some View {
        List {
            Section { Text("Reference index only. No dosing guidance. Confirm exact product, species, indication, interactions and route with your veterinarian. Food-animal meat and milk withdrawal intervals must be documented from the applicable label or veterinarian.").foregroundStyle(.orange) }
            ForEach(drugs.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { d in
                NavigationLink(d) {
                    List {
                        Text("Verify the exact product and all instructions before use. Some products are not approved for every species or food-producing animal.")
                        Link("Animal Drugs @ FDA", destination: URL(string: "https://animaldrugsatfda.fda.gov/adafda/views/#/search")!)
                        Link("DailyMed labels", destination: URL(string: "https://dailymed.nlm.nih.gov/dailymed/")!)
                        Link("Food Animal Residue Avoidance Databank", destination: URL(string: "https://www.farad.org/")!)
                    }.navigationTitle(d)
                }
            }
        }.searchable(text: $search).navigationTitle("Farm Medications")
    }
}
struct FarmMath: View {
    @State private var pounds = ""
    @State private var date = Date()
    @State private var days = 150
    var body: some View {
        Form {
            Section("Weight conversion") {
                TextField("Pounds", text: $pounds).keyboardType(.decimalPad)
                if let p = Double(pounds), p.isFinite, p > 0 { Text(String(format: "%.3f kg", p * 0.45359237)).font(.title2) }
                Text("kg = lb × 0.45359237").foregroundStyle(.secondary)
            }
            Section("Estimated due date") {
                DatePicker("Known breeding date", selection: $date, displayedComponents: .date)
                Stepper("Vet-confirmed gestation estimate: \(days) days", value: $days, in: 1...450)
                if let result = Calendar.current.date(byAdding: .day, value: days, to: date) { Text(result.formatted(date: .abbreviated, time: .omitted)).font(.title2) }
                Text("Estimated date = breeding date + gestation days. Confirm the species-specific estimate with your veterinarian; not a prediction of actual birth.")
            }
        }.navigationTitle("Farm Calculators")
    }
}
struct FarmAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let type: String
    let filename: String
}
struct FarmReport: View {
    @ObservedObject var store: FarmStore
    let initialAnimal: UUID?
    let phone: String
    @State private var animalID: UUID? = nil
    @State private var reportDate = Date()
    @State private var species = FarmSpecies.goat
    @State private var name = ""
    @State private var symptoms = ""
    @State private var onset = ""
    @State private var observations = ""
    @State private var findings = ""
    @State private var care = ""
    @State private var redFlags = false
    @State private var reviewed = false
    @State private var attachments: [FarmAttachment] = []
    @State private var selected: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var message = false
    @State private var status = ""
    @State private var busy = false
    private var animal: FarmAnimal? { store.animals.first { $0.id == animalID } }
    private var report: String {
        let identity = animal.map { $0.name + " (" + $0.species.rawValue + "), tag: " + $0.tag + ", weight: " + $0.weight } ?? name + " (" + species.rawValue + ")"
        return ["VetMate Farm • veterinary assessment request", reportDate.formatted(), "Animal: " + identity, "Concern: " + symptoms, "Onset: " + onset, "Observed signs / measurements: " + observations, "Possible concerns / reviewed notes: " + findings, "Care already provided: " + care, "Urgent signs reported: " + (redFlags ? "Yes — call veterinarian directly" : "Not selected; absence of an emergency is not established"), "Media attachments: " + String(attachments.count), "Owner-entered observations; not an AI diagnosis. Please advise next steps."].joined(separator: "\n\n")
    }
    var body: some View {
        Form {
            identitySection
            observationSection
            mediaSection
            reportSection
        }
        .navigationTitle("Vet Report")
        .onAppear { if animalID == nil { animalID = initialAnimal } }
        .onChange(of: selected) { _, items in load(items) }
        .onChange(of: report) { _, _ in reviewed = false }
        .sheet(isPresented: $camera) {
            FarmCamera { attachment in
                if let attachment { add(attachment) }
            }.ignoresSafeArea()
        }
        .sheet(isPresented: $message) {
            FarmMessage(recipient: phone, body: report, files: attachments) { result in
                switch result {
                case .sent: status = "Messages reports sent; delivery/read status is not verified."
                case .cancelled: status = "Message cancelled. Nothing sent by VetMate."
                case .failed: status = "Message failed. Contact your veterinarian another way."
                @unknown default: status = "Message status unknown."
                }
                message = false
            }
        }
    }
    private var identitySection: some View {
        Section("Animal") {
            Picker("Saved animal", selection: $animalID) {
                Text("Unregistered animal").tag(UUID?.none)
                ForEach(store.animals) { a in Text(a.name + " • " + a.species.rawValue).tag(Optional(a.id)) }
            }
            if animal == nil {
                Picker("Species", selection: $species) { ForEach(FarmSpecies.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Name / tag", text: $name)
            }
        }
    }
    private var observationSection: some View {
        Section("Health assessment") {
            TextField("Concern / wound location", text: $symptoms, axis: .vertical)
            TextField("When it started", text: $onset)
            TextField("Appetite, behavior, temperature, swelling, discharge, pain", text: $observations, axis: .vertical)
            TextField("Possible concerns / findings from your observations or veterinarian", text: $findings, axis: .vertical)
            TextField("Care or medicines already given, times and amounts", text: $care, axis: .vertical)
            Toggle("Emergency warning signs present", isOn: $redFlags)
            if redFlags { Text("Call your veterinarian now. Do not rely on a text message.").foregroundStyle(.red) }
            Text("AI image interpretation: coming soon. No disease is inferred from photos in this build. Media are sent for the veterinarian to assess.").font(.caption).foregroundStyle(.orange)
        }
    }
    private var mediaSection: some View {
        Section("Photos & videos") {
            Button { camera = true } label: { Label("Take photo or video", systemImage: "camera.fill") }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || busy || attachments.count >= 5)
            PhotosPicker(selection: $selected, maxSelectionCount: 5, matching: .any(of: [.images, .videos])) {
                Label("Choose photos or videos", systemImage: "photo.on.rectangle")
            }.disabled(busy || attachments.count >= 5)
            ForEach(attachments) { a in
                HStack {
                    if let img = UIImage(data: a.data), a.type == UTType.jpeg.identifier {
                        Image(uiImage: img).resizable().scaledToFit().frame(width: 54, height: 54)
                    } else { Image(systemName: "video.fill").frame(width: 54) }
                    VStack(alignment: .leading) { Text(a.filename); Text(ByteCountFormatter.string(fromByteCount: Int64(a.data.count), countStyle: .file)).font(.caption) }
                    Spacer()
                    Button(role: .destructive) { attachments.removeAll { $0.id == a.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            Text("Up to 5 files, 20 MB total in this beta; prefer short clips. Review all media before sending. Attachments stay in this draft, not in the saved animal history.").font(.caption)
            if busy { ProgressView("Preparing attachments") }
        }
    }
    private var reportSection: some View {
        Section("Review and send") {
            Text(report).font(.footnote).textSelection(.enabled)
            Toggle("I verified the animal, observations and media", isOn: $reviewed)
            Button { message = true } label: { Label("Text report to veterinarian", systemImage: "message.fill") }
                .disabled(!reviewed || busy || !MFMessageComposeViewController.canSendText() || (!attachments.isEmpty && !MFMessageComposeViewController.canSendAttachments()))
            ShareLink(item: report) { Label("Share report text only", systemImage: "square.and.arrow.up") }.disabled(!reviewed)
            if let animal { Button("Save report text to animal history") {
                status = store.addRecord(animal.id, FarmRecord(kind: "Vet report draft", text: report)) ? "Report text saved." : "Unable to save report."
            }.disabled(!reviewed) }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.orange) }
            Text("Messages opens for your review; you must press Send. Your carrier or recipient may limit media size. If attachments cannot be sent, share text and contact the veterinarian directly.").font(.caption)
        }
    }
    private func add(_ item: FarmAttachment) {
        guard attachments.count < 5, item.data.count <= 20_000_000 - attachments.reduce(0, { $0 + $1.data.count }) else {
            status = "Attachment not added: limit is 5 files and 20 MB total. Choose a shorter video."; return
        }
        attachments.append(item); reviewed = false
    }
    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, !busy else { return }
        busy = true; reviewed = false
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { status = "One attachment could not be loaded."; continue }
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    let t = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) }) ?? .movie
                    add(FarmAttachment(data: data, type: t.identifier, filename: "Farm-video." + (t.preferredFilenameExtension ?? "mov")))
                } else if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.72) {
                    add(FarmAttachment(data: jpeg, type: UTType.jpeg.identifier, filename: "Farm-photo.jpg"))
                } else { status = "Image format could not be prepared." }
            }
            busy = false; selected = []
        }
    }
}
struct FarmCamera: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let completion: (FarmAttachment?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera)?.filter { $0 == UTType.image.identifier || $0 == UTType.movie.identifier } ?? [UTType.image.identifier]
        p.videoMaximumDuration = 15
        p.videoQuality = .typeMedium
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: FarmCamera
        init(_ parent: FarmCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL, let data = try? Data(contentsOf: url) {
                parent.completion(FarmAttachment(data: data, type: UTType.quickTimeMovie.identifier, filename: "Farm-video.mov"))
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.72) {
                parent.completion(FarmAttachment(data: data, type: UTType.jpeg.identifier, filename: "Farm-photo.jpg"))
            } else { parent.completion(nil) }
            parent.dismiss()
        }
    }
}
struct FarmMessage: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let files: [FarmAttachment]
    let completion: (MessageComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let p = MFMessageComposeViewController()
        p.messageComposeDelegate = context.coordinator
        if !recipient.isEmpty { p.recipients = [recipient] }
        p.body = body
        var missed = 0
        for file in files {
            if !p.addAttachmentData(file.data, typeIdentifier: file.type, filename: file.id.uuidString + "-" + file.filename) { missed += 1 }
        }
        if missed > 0 { p.body = body + "\n\nWARNING: " + String(missed) + " attachment(s) could not be included. Contact sender for missing media." }
        return p
    }
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: FarmMessage
        init(_ parent: FarmMessage) { self.parent = parent }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { parent.completion(result) }
    }
}
