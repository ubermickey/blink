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
  func hasActiveSubscriptions() -> Bool { return true }
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

import SwiftUI
struct NewIntroPageWindow: View {
  var urlHandler: ((URL) -> Void)?
  var dismissHandler: (() -> Void)?
  var body: some View { EmptyView() }
}
#endif
