#if BLINK_FREE_BUILD
import Foundation
import Combine

public enum CustomerTier {
  case Free, Plus, Classic, TestFlight
}

public enum EntitlementPeriodType {
  case Trial, Intro, Normal
}

class EntitlementsManager: ObservableObject {
  static let shared = EntitlementsManager()
  func groupsCheckViolation() -> Bool { return false }
  func earlyBirdEntitlement() -> Bool { return true }
  func customerTier() -> CustomerTier { return .Free }
  func currentPeriodType() -> EntitlementPeriodType { return .Normal }
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
