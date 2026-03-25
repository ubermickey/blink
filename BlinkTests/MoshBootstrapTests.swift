//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2023 Blink Mobile Shell Project
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

import Combine
import XCTest
import Foundation

import SSH

@testable import Blink

final class MoshBootstrapTests: XCTestCase {
  var cancellableBag: Set<AnyCancellable> = []
  
  func testMoshBootstrap() throws {
    print("connecting...")
    
    let expectConn = self.expectation(description: "Connection established")
    
    var connection: SSHClient!
    SSHClient.dial(SSHClientConfig.testHost, with: .testConfig)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { conn in
          connection = conn
          expectConn.fulfill()
        }).store(in: &cancellableBag)

    wait(for: [expectConn], timeout: 5)

    print("connected")
    
    let expectBootstrap = self.expectation(description: "Mosh bootstrapped")
    let logger = MoshLogger(output: OutputStream(file: stdout))

    InstallStaticMosh(promptUser: false, logger: logger)
      .start(on: connection)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { moshServerPath in
          print("Mosh server path at: \(moshServerPath)")
          expectBootstrap.fulfill()
        }
      ).store(in: &cancellableBag)
    
    wait(for: [expectBootstrap], timeout: 30)
  }
  
  func testMoshDownloadBinaries() throws {
    guard ProcessInfo.processInfo.environment["FIXTURE_ALLOW_NETWORK_DOWNLOADS"] == "1" else {
      throw XCTSkip("Skipping internet-dependent Mosh binary download test in fixture-backed automation.")
    }

    let logger = MoshLogger(output: OutputStream(file: stdout), logLevel: .info)
    let moshBootstrap = InstallStaticMosh(promptUser: false, logger: logger)
    
    moshBootstrap.getMoshServerBinary(platform: .Darwin, architecture: .X86_64)
      .assertNoFailure()
      .sink(test: self)

    moshBootstrap.getMoshServerBinary(platform: .Darwin, architecture: .Arm64)
      .assertNoFailure()
      .sink(test: self)
    
    moshBootstrap.getMoshServerBinary(platform: .Linux, architecture: .Amd64)
      .assertNoFailure()
      .sink(test: self)
    
    moshBootstrap.getMoshServerBinary(platform: .Linux, architecture: .Arm64)
      .assertNoFailure()
      .sink(test: self)
    
    moshBootstrap.getMoshServerBinary(platform: .Linux, architecture: .Armv7)
      .assertNoFailure()
      .sink(test: self)
  }
}

// TODO Test getting parameters from expected Mosh output. Important in case we find weird cases, but not critical.
// TODO - We could test the Bootstrap request flow, separating it to a different object. Complicated and not sure what extra insight we would get from it.
// TODO Test configurations from .ssh/config + parameters. How? This will have to go to the QA instructions.

extension SSHClientConfig {
  private static let env = ProcessInfo.processInfo.environment

  private static func nonEmptyEnv(_ key: String) -> String? {
    guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func firstEnv(_ keys: [String], default defaultValue: String) -> String {
    for key in keys {
      if let value = nonEmptyEnv(key) {
        return value
      }
    }
    return defaultValue
  }

  static let testHost: String = {
#if targetEnvironment(simulator)
    return firstEnv(["BLINK_TEST_HOST", "FIXTURE_SIM_HOST"], default: "localhost")
#else
    return firstEnv(["BLINK_TEST_HOST", "FIXTURE_DEVICE_HOST", "FIXTURE_SIM_HOST"], default: "localhost")
#endif
  }()

  static let testConfig = SSHClientConfig(
    user: firstEnv(["BLINK_TEST_USER"], default: "regular"),
    port: firstEnv(["BLINK_TEST_PORT", "FIXTURE_SSH_PORT"], default: "2222"),
    authMethods: [AuthPassword(with: firstEnv(["BLINK_TEST_PASSWORD"], default: "regular"))],
    loggingVerbosity: .debug
  )
}
