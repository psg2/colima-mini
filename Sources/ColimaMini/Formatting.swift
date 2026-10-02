import Foundation

func memoryText(_ bytes: Double) -> String {
  bytes >= 1_073_741_824
    ? String(format: "%.2f GiB", bytes / 1_073_741_824)
    : String(format: "%.0f MiB", bytes / 1_048_576)
}
