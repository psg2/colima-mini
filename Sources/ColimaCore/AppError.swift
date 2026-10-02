import Foundation

package enum AppError: LocalizedError {
  case message(String)
  package var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}
