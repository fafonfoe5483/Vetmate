import SwiftUI
import WebKit
import Vision
import PhotosUI
import LocalAuthentication
import UserNotifications

final class VetMateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

@main struct VetMateApp: App {
    private let notificationDelegate = VetMateNotificationDelegate()
    init() { UNUserNotificationCenter.current().delegate = notificationDelegate }
    var body: some Scene { WindowGroup { ContentView().preferredColorScheme(.dark) } }
}

struct ContentView: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            WebApp().tabItem { Label("VetMate", systemImage: "pawprint.fill") }.tag(0)
            LabelScanner().tabItem { Label("Label Scan", systemImage: "viewfinder") }.tag(1)
            ClinicalWorkspace().tabItem { Label("Clinical", systemImage: "heart.text.square") }.tag(2)
            FarmWorkspace().tabItem { Label("Farm", systemImage: "leaf.fill") }.tag(3)
        }.tint(.blue)
    }
}

struct WebApp: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 3/255, green: 10/255, blue: 17/255, alpha: 1)
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web.loadHTMLString("<h1>VetMate</h1><p>Bundled resources unavailable.</p>", baseURL: nil)
        }
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct LabelScanner: View {
    @State private var item: PhotosPickerItem?
    @State private var text = ""
    @State private var status = "Choose a clear photograph of a printed medication label."
    @State private var camera = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Native label scanner").font(.title2.bold())
                    Text("Local Apple Vision text recognition. Review every character against the original label.").foregroundStyle(.secondary)
                    Button { camera = true } label: { Label("Take photo", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Choose photo", systemImage: "photo").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    Text(status).foregroundStyle(.secondary)
                    TextEditor(text: $text).frame(minHeight: 160).padding(8)
                        .scrollContentBackground(.hidden).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    ShareLink(item: text).disabled(text.isEmpty)
                    Link("Search official medication labels", destination: URL(string: "https://dailymed.nlm.nih.gov/dailymed/")!)
                    Text("Never use OCR alone to identify a medication or calculate a dose. This prototype is not clinically validated. Use fictional records and test labels without client information.").font(.footnote).foregroundStyle(.yellow)
                }.padding()
            }.navigationTitle("VetMate Scan")
                .sheet(isPresented: $camera) { Camera { data in if let data { recognize(data) } }.ignoresSafeArea() }
                .onChange(of: item) { _, newItem in
                    task?.cancel()
                    guard let newItem else { return }
                    task = Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self), !Task.isCancelled { recognize(data) }
                        else if !Task.isCancelled { status = "Unable to load photograph." }
                    }
                }
        }
    }
    @MainActor private func recognize(_ data: Data) {
        task?.cancel()
        text = ""
        status = "Reading label…"
        task = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> String? in
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do {
                    try handler.perform([request])
                    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                } catch { return nil }
            }.value
            guard !Task.isCancelled else { return }
            text = result ?? ""
            status = text.isEmpty ? "No readable text. Retake the photo or enter the name manually." : "Review the detected text against the actual label."
        }
    }
}

struct Camera: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: Camera
        init(_ parent: Camera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            parent.completion(image?.jpegData(compressionQuality: 0.95))
            parent.dismiss()
        }
    }
}
