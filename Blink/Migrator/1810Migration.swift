//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2024 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import Foundation
import CoreData


class MigrationFileProviderReplicatedExtension: MigrationStep {
  var version: Int { get { 1810 } }

  func execute() throws {
    // Replace old FileProvider extension items with the new FileProvider Replicated Extension
    for host in BKHosts.allHosts() {
      guard let json = host.fpDomainsJSON, !json.isEmpty
      else {
        continue
      }

      let domains = FileProviderDomain.listFrom(jsonString: json)
      if domains.count > 0 {
        domains.forEach { domain in
          if !domain.useReplicatedExtension {
            domain.useReplicatedExtension = true
          }
        }
        host.fpDomainsJSON = FileProviderDomain.toJson(list: domains)

        BKHosts._replaceHost(host)
      }
    }

    // Do we need it or does it happen on its own?
    BKiCloudSyncHandler.shared()?.check(forReachabilityAndSync: nil)

    self.deleteFileProviderStorage()
  }

  private func deleteFileProviderStorage() {
    // Clean up the old File Provider path
    guard let fileProviderURL = self.legacyDocumentStorageURL() else {
      print("Skipping legacy File Provider storage cleanup because document storage is unavailable.")
      return
    }

    guard let contentURLs = try? FileManager.default.contentsOfDirectory(at: fileProviderURL, includingPropertiesForKeys: nil, options: []) else {
      print("No contents found at \(fileProviderURL.path)")
      return
    }

    for url in contentURLs {
      do {
        try FileManager.default.removeItem(at: url)
        print("Removed: \(url.path)")
      } catch {
        print("Failed to remove \(url.path): \(error)")
      }
    }
  }

  private func legacyDocumentStorageURL() -> URL? {
    guard let builtInPlugInsURL = Bundle.main.builtInPlugInsURL,
          let plugInURLs = try? FileManager.default.contentsOfDirectory(
            at: builtInPlugInsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
          ),
          let fileProviderExtensionURL = plugInURLs.first(where: self._isEmbeddedFileProviderExtension),
          let documentGroupIdentifier = self._documentGroupIdentifier(for: fileProviderExtensionURL),
          FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: documentGroupIdentifier) != nil else {
      return nil
    }

    return NSFileProviderManager.default.documentStorageURL
  }

  private func _isEmbeddedFileProviderExtension(_ url: URL) -> Bool {
    guard url.pathExtension == "appex",
          let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any],
          let extensionInfo = info["NSExtension"] as? [String: Any],
          let extensionPointIdentifier = extensionInfo["NSExtensionPointIdentifier"] as? String else {
      return false
    }

    return extensionPointIdentifier == "com.apple.fileprovider-nonui"
  }

  private func _documentGroupIdentifier(for extensionURL: URL) -> String? {
    guard let info = NSDictionary(contentsOf: extensionURL.appendingPathComponent("Info.plist")) as? [String: Any],
          let extensionInfo = info["NSExtension"] as? [String: Any] else {
      return nil
    }

    return extensionInfo["NSExtensionFileProviderDocumentGroup"] as? String
  }
}
