import SwiftUI
import AppKit
import Security

@main
struct GoFileManagerApp: App {
    var body: some Scene {
        WindowGroup("GoFile Personal File Manager") { ContentView() }
            .defaultSize(width: 980, height: 680)
    }
}

@MainActor
final class GoFileModel: ObservableObject {
    @Published var token = ""
    @Published var folderID = ""
    @Published var status = "Enter your GoFile account token, then choose a file."
    @Published var files: [GoFileItem] = []
    @Published var isBusy = false
    private let keychainService = "com.julianb183.gofile-manager"

    init() { token = loadToken() }

    func saveToken() {
        guard !token.isEmpty else { status = "Enter a token first."; return }
        let data = Data(token.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "account-token"]
        SecItemDelete(query as CFDictionary)
        let add = query.merging([kSecValueData as String: data]) { _, new in new }
        let result = SecItemAdd(add as CFDictionary, nil)
        status = result == errSecSuccess ? "Token saved securely in the macOS Keychain." : "Could not save the token (Keychain error \(result))."
    }

    func chooseAndUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await upload(url) }
    }

    func refresh() { Task { await loadContents() } }

    private func upload(_ file: URL) async {
        guard !token.isEmpty else { status = "Enter and save your GoFile account token first."; return }
        isBusy = true; defer { isBusy = false }
        do {
            var request = URLRequest(url: URL(string: "https://upload.gofile.io/uploadfile")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let boundary = "GoFileBoundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let data = try Data(contentsOf: file)
            var body = Data()
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\n".utf8))
            body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8)); body.append(data); body.append(Data("\r\n".utf8))
            if !folderID.isEmpty { body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"folderId\"\r\n\r\n\(folderID)\r\n".utf8)) }
            body.append(Data("--\(boundary)--\r\n".utf8))
            let (_, response) = try await URLSession.shared.upload(for: request, from: body)
            guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
            status = http.statusCode == 200 ? "Uploaded \(file.lastPathComponent)." : "Upload failed with HTTP \(http.statusCode)."
        } catch { status = "Upload failed: \(error.localizedDescription)" }
    }

    private func loadContents() async {
        guard !token.isEmpty, !folderID.isEmpty else { status = "Enter a token and folder ID to list contents."; return }
        isBusy = true; defer { isBusy = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.gofile.io/contents/\(folderID)")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.badResponse }
            let decoded = try JSONDecoder().decode(GoFileResponse.self, from: data)
            files = decoded.data.children?.values.sorted { $0.name < $1.name } ?? []
            status = "Loaded \(files.count) item(s)."
        } catch { status = "Could not load contents: \(error.localizedDescription)" }
    }

    private func loadToken() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "account-token", kSecReturnData as String: true]
        var result: AnyObject?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct GoFileItem: Codable, Identifiable {
    var id: String
    var name: String
    var type: String?
    var size: Int64?
    var downloadPage: String?
    enum CodingKeys: String, CodingKey { case id, name, type, size, downloadPage }
}
struct GoFileData: Codable { var children: [String: GoFileItem]? }
struct GoFileResponse: Codable { var data: GoFileData }
enum APIError: Error { case badResponse }

struct ContentView: View {
    @StateObject private var model = GoFileModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: "externaldrive.fill.badge.icloud").foregroundStyle(.cyan); Text("GOFILE PERSONAL FILE MANAGER").font(.title2.monospaced()); Spacer(); if model.isBusy { ProgressView() } }
            GroupBox("Account") {
                HStack { SecureField("GoFile account token", text: $model.token); Button("Save Token") { model.saveToken() } }
                Text("The token is stored in macOS Keychain and is never written to the project.").font(.caption).foregroundStyle(.secondary)
            }
            HStack { TextField("Folder ID for listing/upload", text: $model.folderID); Button("Refresh") { model.refresh() }; Button("Upload File") { model.chooseAndUpload() }.buttonStyle(.borderedProminent) }
            List(model.files) { file in
                HStack { Image(systemName: file.type == "folder" ? "folder" : "doc"); Text(file.name); Spacer(); Text(file.type ?? "file").foregroundStyle(.secondary) }
            }
            Text(model.status).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            Text("Uses GoFile's authenticated API. Keep your account token private; anyone with it can access your account.").font(.caption).foregroundStyle(.orange)
        }.padding(24).frame(minWidth: 760, minHeight: 520)
    }
}
