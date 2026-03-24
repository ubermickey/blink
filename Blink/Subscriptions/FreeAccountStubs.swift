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

struct WalkthroughView: View {
  var body: some View { EmptyView() }
}

struct PageCtx {
  let proxy: GeometryProxy
  let dynamicTypeSize: DynamicTypeSize
  var horizontalCompact: Bool = false
  var verticalCompact: Bool = false
  var portrait: Bool = true
  func pagePadding() -> EdgeInsets { EdgeInsets(top: 20, leading: 10, bottom: 20, trailing: 10) }
}

struct NewOfferingsView: View {
  var classicOffering: Bool = false
  var ctx: PageCtx? = nil
  var purchaseCompletedHandler: (() -> Void)? = nil
  var urlHandler: ((URL) -> Void)? = nil
  var dismissHandler: (() -> Void)? = nil
  var body: some View { EmptyView() }
}

public struct Entitlement: Identifiable, Equatable, Hashable {
  public var id: String
  public var name: String = ""
  public var isActive: Bool = false
}
#endif
