//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
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
import Network

@testable import BlinkCode

var OperationId: UInt32 = 0

class BlinkCodeTests: XCTestCase {
  var service: CodeFileSystemService? = nil
  var serviceURL: URL!
  var fixtureRoot: URL!
  var sourceFile: URL!
  var sourceData: Data!
  static var nextPort: UInt16 = 19015

  private static func reservePort() -> UInt16 {
    defer { nextPort += 1 }
    return nextPort
  }

  private func localURI(_ url: URL) -> URI {
    try! URI(string: "blinkfs:\(url.path)")
  }

  override func setUpWithError() throws {
    OperationId = 0
    fixtureRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("BlinkCodeTests-\(UUID().uuidString)", isDirectory: true)
    sourceFile = fixtureRoot.appendingPathComponent("build.token")
    sourceData = Data("blink-code".utf8)
    try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    try sourceData.write(to: sourceFile)

    let port = Self.reservePort()
    serviceURL = URL(string: "ws://127.0.0.1:\(port)")!
    service = try CodeFileSystemService(listenOn: NWEndpoint.Port(rawValue: port)!,
                                        tls: false,
                                        finished: { _ in })
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
  }

  override func tearDownWithError() throws {
    service = nil
    try? FileManager.default.removeItem(at: fixtureRoot)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
  }

  func testVSCode() throws {
    throw XCTSkip("VSCode integration is not part of verify-fast.")
  }
  
  func testStat() throws {
    let task = URLSession.shared.webSocketTask(with: serviceURL)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    let req = StatFileSystemRequest(uri: localURI(sourceFile))
    
    let (response, responseContent) = try task.sendCodeFileSystemRequest(req,
                                                                         test: self)
    
    XCTAssert(!response.isEmpty)
    XCTAssertNil(responseContent)
    
    guard let fileStat = try? JSONDecoder().decode(FileStat.self, from: response) else {
      XCTFail("Could not decode JSON")
      return
    }
    print(fileStat)
    XCTAssertTrue(fileStat.type == FileType.File)
  }

  func testReadDirectory() throws {
    let task = URLSession.shared.webSocketTask(with: serviceURL)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    let req = ReadDirectoryFileSystemRequest(uri: localURI(fixtureRoot))
    
    let (response, responseContent) = try task.sendCodeFileSystemRequest(req, test: self)
    
    XCTAssertTrue(!response.isEmpty)
    XCTAssertNil(responseContent)
    
    print(String(data: response, encoding: .utf8))
    guard let items = try? JSONDecoder().decode([DirectoryTuple].self, from: response) else {
      XCTFail("Could not decode JSON")
      return
    }
    print(items)
    XCTAssertTrue(items.contains { $0.name == sourceFile.lastPathComponent })
  }

  // TODO Test. Fail if no create. Create file. Overwrite file. Fail if overwrite.
  func testWriteFile() throws {
    let targetFile = fixtureRoot.appendingPathComponent("createtest")
    FileManager.default.createFile(atPath: targetFile.path, contents: Data(), attributes: nil)

    let task = URLSession.shared.webSocketTask(with: serviceURL)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    let uri = localURI(targetFile)
    let filePath = uri.rootPath.filesAtPath
    let req = WriteFileSystemRequest(uri: uri, options: .init(overwrite: true, create: false))
    let content = "Hello world".data(using: .utf8)

    let (response, responseContent) = try task.sendCodeFileSystemRequest(req,
                                                                         binaryData: content,
                                                                         test: self)
    XCTAssertTrue(response.isEmpty)
    XCTAssertTrue(responseContent == nil)

    let readContent = try String(contentsOfFile: filePath).data(using: .utf8)
    XCTAssertTrue(content == readContent)
  }

  // TODO Try to recreate and check error
  func testCreateDirectory() throws {
    let task = URLSession.shared.webSocketTask(with: serviceURL)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    let uri = localURI(fixtureRoot.appendingPathComponent("newdir"))
    let path = uri.rootPath.filesAtPath
    let req  = CreateDirectoryFileSystemRequest(uri: uri)

    let (response, responseContent) = try task.sendCodeFileSystemRequest(req,
                                                                         binaryData: nil,
                                                                         test: self)
    XCTAssertTrue(response.isEmpty)
    XCTAssertTrue(responseContent == nil)

    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    XCTAssertTrue(exists)
    XCTAssertTrue(isDir.boolValue)
  }

  func testRename() throws {
    try FileManager.default.createDirectory(
      at: fixtureRoot.appendingPathComponent("newdir"),
      withIntermediateDirectories: true
    )

    let task = URLSession.shared.webSocketTask(with: serviceURL)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    let uri     = localURI(fixtureRoot.appendingPathComponent("newdir"))
    let path    = uri.rootPath.filesAtPath
    let newUri  = localURI(fixtureRoot.appendingPathComponent("newpathdir"))
    let newPath = newUri.rootPath.filesAtPath
    let req  = RenameFileSystemRequest(oldUri: uri,
                                       newUri: newUri,
                                       options: .init(overwrite:false))

    let (response, responseContent) = try task.sendCodeFileSystemRequest(req,
                                                                         binaryData: nil,
                                                                         test: self)

    XCTAssertTrue(response.isEmpty)
    XCTAssertTrue(responseContent == nil)

    var isDir: ObjCBool = false
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    let exists = FileManager.default.fileExists(atPath: newPath, isDirectory: &isDir)
    XCTAssertTrue(exists)
    XCTAssertTrue(isDir.boolValue)
  }

  func testDelete() throws {
    try FileManager.default.createDirectory(
      at: fixtureRoot.appendingPathComponent("newdir"),
      withIntermediateDirectories: true
    )

    let task = URLSession.shared.webSocketTask(with: serviceURL)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    let uri = localURI(fixtureRoot.appendingPathComponent("newdir"))
    let path = uri.rootPath.filesAtPath
    let req  = DeleteFileSystemRequest(uri: uri,
                                       options: .init(recursive: true))

    let (response, responseContent) = try task.sendCodeFileSystemRequest(req,
                                                                         binaryData: nil,
                                                                         test: self)

    XCTAssertTrue(response.isEmpty)
    XCTAssertTrue(responseContent == nil)

    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    XCTAssertFalse(exists)
  }
}

extension URLSessionWebSocketTask {
  fileprivate func sendCodeFileSystemRequest<T: Codable>(_ req: T, binaryData: Data? = nil, test: XCTestCase) throws -> (Data, Data?) {
    let expectation = XCTestExpectation(description: "File System Request fulfilled")

    let payload = CodeSocketMessagePayload(encodedData: try JSONEncoder().encode(req),
                                           binaryData: binaryData)
    let header = CodeSocketMessageHeader(type: payload.type,
                                         operationId: OperationId,
                                         referenceId: 1)
    let message = header.encoded + payload.encoded
    self.send(.data(message)) { error in if let error = error { XCTFail("\(error)") }}

    var responseEncodedData: Data = Data()
    var responseBinaryData:  Data? = nil

    self.receive { result in
      switch result {
      case .success(let response):
        switch response {
        case .data(let data):
          var buffer = data

          guard let respHeader = CodeSocketMessageHeader(buffer[0..<CodeSocketMessageHeader.encodedSize]) else {
            XCTFail("Could not parse response header")
            return
          }
          print(respHeader)

          XCTAssertTrue(respHeader.referenceId == header.operationId)

          buffer = buffer.advanced(by: CodeSocketMessageHeader.encodedSize)
          print(String(data: buffer, encoding: .utf8))

          guard let respPayload = CodeSocketMessagePayload(buffer, type: respHeader.type) else {
            XCTFail("Could not parse response payload")
            return
          }
          responseEncodedData = respPayload.encodedData
          responseBinaryData  = respPayload.binaryData

        default:
          XCTFail("Wrong response type")
        }
        case .failure(let error):
          XCTFail("\(error)")
      }
      expectation.fulfill()
    }

    test.wait(for: [expectation], timeout: 5.0)

    return (responseEncodedData, responseBinaryData)
  }
}

extension URI {
  // The URI always comes from decoding messages, so we add a helper to simulate that.
  init(_ str: String) {
    let out = try! JSONEncoder().encode(str)
    self = try! JSONDecoder().decode(URI.self, from: out)
  }
}
