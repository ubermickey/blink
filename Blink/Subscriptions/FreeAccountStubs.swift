#if BLINK_FREE_BUILD
import Foundation
import Combine

class EntitlementsManager: ObservableObject {
  static let shared = EntitlementsManager()
  func groupsCheckViolation() -> Bool { return false }
  func earlyBirdEntitlement() -> Bool { return true }
  @Published var activeEntitlements: Set<String> = []
  @Published var unlockStatus: Bool = true
}

class PurchasesUserModel: ObservableObject {
  static let shared = PurchasesUserModel()
}

class AppStoreEntitlementsSource {
  static let shared = AppStoreEntitlementsSource()
}

let BLINK_APP_FONT_NAME: String = Bundle.main.infoDictionary?["BLINK_APP_FONT"] as? String ?? "JetBrains Mono"
#endif
