import Foundation

func memoryText(_ bytes: Double) -> String {
  bytes >= 1_073_741_824
    ? String(format: "%.2f GiB", bytes / 1_073_741_824)
    : String(format: "%.0f MiB", bytes / 1_048_576)
}

func bytesText(_ bytes: Double?) -> String {
  guard let bytes, bytes.isFinite, bytes >= 0 else { return "Unknown" }
  if bytes == 0 { return "0 B" }
  for (name, scale) in [
    ("TiB", pow(1024.0, 4)), ("GiB", pow(1024.0, 3)), ("MiB", pow(1024.0, 2)), ("KiB", 1024.0),
  ] where bytes >= scale {
    return String(format: "%.2f %@", bytes / scale, name)
  }
  return String(format: "%.0f B", bytes)
}

func countText(_ count: Int, _ singular: String) -> String {
  "\(count) " + singular + (count == 1 ? "" : "s")
}
