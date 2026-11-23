import Foundation
import Combine

@MainActor final class DocumentLibrary: ObservableObject {
    @Published private(set) var documents: [ScanDocument] = []
    private let root: URL
    private var index: URL { root.appendingPathComponent("library.json") }

    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Scans", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: index.path) {
            documents = try JSONDecoder().decode([ScanDocument].self, from: Data(contentsOf: index))
        }
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func pageURL(_ page: DocumentPage, document: UUID) -> URL { folder(document).appendingPathComponent(page.file) }
    func document(_ id: UUID) -> ScanDocument? { documents.first { $0.id == id } }
    private func persist() throws { try JSONEncoder().encode(documents).write(to: index, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }

    func create() throws -> UUID {
        let id = UUID()
        let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH.mm"
        let document = ScanDocument(id: id, title: "扫描 \(formatter.string(from: Date()))", created: Date(), pages: [])
        try FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
        documents.insert(document, at: 0)
        do { try persist() } catch { documents.removeAll { $0.id == id }; throw error }
        return id
    }

    func append(_ page: DocumentPage, document: UUID) throws {
        guard let index = documents.firstIndex(where: { $0.id == document }), !documents[index].pages.contains(where: { $0.file == page.file }) else { return }
        documents[index].pages.append(page)
        do { try persist() } catch { documents[index].pages.removeLast(); throw error }
    }

    func rename(_ id: UUID, title: String) throws {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let old = documents[index].title
        documents[index].title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        do { try persist() } catch { documents[index].title = old; throw error }
    }

    func rotate(_ page: UUID, document: UUID) throws {
        guard let d = documents.firstIndex(where: { $0.id == document }), let p = documents[d].pages.firstIndex(where: { $0.id == page }) else { return }
        let old = documents[d].pages[p].rotation
        documents[d].pages[p].rotation = (old + 90) % 360
        do { try persist() } catch { documents[d].pages[p].rotation = old; throw error }
    }
    func reorder(_ offsets: IndexSet, to target: Int, document: UUID) throws {
        guard let d = documents.firstIndex(where: { $0.id == document }) else { return }
        let old = documents[d].pages
        let moving = offsets.sorted().map { old[$0] }
        var rest = old.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: target - offsets.filter { $0 < target }.count)
        documents[d].pages = rest
        do { try persist() } catch { documents[d].pages = old; throw error }
    }
    func removePage(_ page: UUID, document: UUID) throws {
        guard let d = documents.firstIndex(where: { $0.id == document }), let p = documents[d].pages.firstIndex(where: { $0.id == page }) else { return }
        let old = documents[d].pages
        let removed = documents[d].pages.remove(at: p)
        do { try persist() } catch { documents[d].pages = old; throw error }
        try? FileManager.default.removeItem(at: pageURL(removed, document: document))
    }
    func remove(_ id: UUID) throws {
        let old = documents
        documents.removeAll { $0.id == id }
        do { try persist() } catch { documents = old; throw error }
        try? FileManager.default.removeItem(at: folder(id))
    }
}
