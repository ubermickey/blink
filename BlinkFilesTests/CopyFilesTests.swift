//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2021 Blink Mobile Shell Project
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

import XCTest
import Combine

@testable import BlinkFiles

class CopyFilesTests: XCTestCase {
  var cancellables: [AnyCancellable] = []
  var fixtureRoot: URL!
  var sourceDir: URL!
  var sourceFile: URL!
  var destinationDir: URL!
  var sourceFileData: Data!
  
  override func setUpWithError() throws {
    fixtureRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("CopyFilesTests-\(UUID().uuidString)", isDirectory: true)
    sourceDir = fixtureRoot.appendingPathComponent("source", isDirectory: true)
    destinationDir = fixtureRoot.appendingPathComponent("destination", isDirectory: true)
    sourceFile = sourceDir.appendingPathComponent("payload.txt")
    sourceFileData = Data(repeating: 0x5a, count: 32 * 1024)

    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
    try sourceFileData.write(to: sourceFile)
  }
  
  override func tearDownWithError() throws {
    cancellables.removeAll()
    if let fixtureRoot {
      try? FileManager.default.removeItem(at: fixtureRoot)
    }
  }
  
  func testCopyFileFrom() throws {
    self.continueAfterFailure = false
    var totalWritten: UInt64 = 0
    let expectFileCopied = self.expectation(description: "File Copied")
    
    Local().cloneWalkTo(destinationDir.path).flatMap { destDir -> CopyProgressInfoPublisher in
      return Local().cloneWalkTo(self.sourceFile.path)
        .flatMap { destDir.copy(from: [$0]) }
        .eraseToAnyPublisher()
    }.sink(receiveCompletion: { completion in
      switch completion {
      case .finished:
        expectFileCopied.fulfill()
      case .failure(let error):
        XCTFail("Crash \(error)")
      }
    }, receiveValue: { report in
      totalWritten += report.written
    }).store(in: &cancellables)
    
    
    wait(for: [expectFileCopied], timeout: 1000)
    
    let copiedFile = destinationDir.appendingPathComponent(sourceFile.lastPathComponent)
    XCTAssertEqual(totalWritten, UInt64(sourceFileData.count))
    XCTAssertEqual(try Data(contentsOf: copiedFile), sourceFileData)
  }
  
  func testCopyFrom() throws {
    self.continueAfterFailure = false
    let expectStructureCopied = self.expectation(description: "Structure Copied")
    
    Local().cloneWalkTo(destinationDir.path).flatMap { destDir -> CopyProgressInfoPublisher in
      return Local().cloneWalkTo(self.sourceDir.path)
        .flatMap { destDir.copy(from: [$0]) }
        .eraseToAnyPublisher()
    }.sink(receiveCompletion: { completion in
      switch completion {
      case .finished:
        expectStructureCopied.fulfill()
      case .failure(let error):
        XCTFail("Crash \(error)")
      }
    }, receiveValue: { report in
      print("\(report.name) - \(report.written) - \(report.size)")
    }).store(in: &cancellables)
    
    wait(for: [expectStructureCopied], timeout: 1000)

    let copiedRoot = destinationDir.appendingPathComponent(sourceDir.lastPathComponent)
    XCTAssertTrue(FileManager.default.fileExists(atPath: copiedRoot.path))
    XCTAssertEqual(
      try Data(contentsOf: copiedRoot.appendingPathComponent(sourceFile.lastPathComponent)),
      sourceFileData
    )
  }
}
