import Foundation

struct TrashService {
    func moveToTrash(_ url: URL) -> Result<URL?, Error> {
        do {
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            return .success(destination as URL?)
        } catch {
            return .failure(error)
        }
    }
}
