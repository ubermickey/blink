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

final class FileBox {
  var file: File?
}

class LocalFilesTests: XCTestCase {
  var cancellableBag: [AnyCancellable] = []
  var fixtureRoot: URL!
  var nestedDir: URL!
  var sourceFile: URL!
  var sourceData: Data!
  
  override func setUpWithError() throws {
    cancellableBag.removeAll()
    fixtureRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("LocalFilesTests-\(UUID().uuidString)", isDirectory: true)
    nestedDir = fixtureRoot.appendingPathComponent("nested", isDirectory: true)
    sourceFile = fixtureRoot.appendingPathComponent("source.bin")
    sourceData = Data("sample-local-file".utf8)

    try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
    try sourceData.write(to: sourceFile)
    try Data("nested-value".utf8).write(to: nestedDir.appendingPathComponent("child.txt"))
  }
  override func tearDownWithError() throws {
    cancellableBag.removeAll()
    if let fixtureRoot {
      try? FileManager.default.removeItem(at: fixtureRoot)
    }
  }
  
  func testDirectory() throws {
    let f = Local()
    let expectation = self.expectation(description: "Local")
    
    f.walkTo(fixtureRoot.path)
      .flatMap { $0.directoryFilesAndAttributes() }
      .assertNoFailure()
      .sink { items in
        XCTAssertTrue(items.count > 0)
        dump(items)
        expectation.fulfill()
      }.store(in: &cancellableBag)
    
    wait(for: [expectation], timeout: 1)
  }
  
  func testWalk() throws {
    let f = Local()
    let dirWalk = self.expectation(description: "Regular directory")
    
    // Absolute
    f.walkTo(fixtureRoot.path)
      .assertNoFailure()
      .sink { dir in
        XCTAssertTrue(dir.current == self.fixtureRoot.path, "Current dir is \(dir.current)")
        dirWalk.fulfill()
      }.store(in: &cancellableBag)
    
    wait(for: [dirWalk], timeout: 1)
    
    // Missing path
    let missingWalk = self.expectation(description: "Missing path")
    f.walkTo(fixtureRoot.appendingPathComponent("missing").path)
      .catch { err -> Just<Translator> in
        let err = err as! LocalFileError
        XCTAssertTrue(err.msg == "No such file or directory.", "Received \(err)")
        return Just(f)
      }.sink { dir in
        XCTAssertTrue(dir.current == f.current)
        missingWalk.fulfill()
      }.store(in: &cancellableBag)
    
    wait(for: [missingWalk], timeout: 1)
    
    // Relative
    let relativeWalk = self.expectation(description: "Relative walk")
    f.walkTo(fixtureRoot.path)
      .flatMap { $0.walkTo("nested") }
      .assertNoFailure()
      .sink { dir in
        XCTAssertTrue(dir.current == self.nestedDir.path, "Current dir is \(dir.current)")
        relativeWalk.fulfill()
      }.store(in: &cancellableBag)
    
    wait(for: [relativeWalk], timeout: 1)
  }
  
  func testFileRead() throws {
    self.continueAfterFailure = false
    // For SFTP it will be useful to have the channel reachable, and then stop it through a timer to test the reconnect.
    let f = Local()
    let expectation = self.expectation(description: "Buffer Complete")
    let fileBox = FileBox()
    
    // TODO Explicitely close the file or do it once it gets
    // dumped.
    f.walkTo(sourceFile.path)
      .flatMap { (translator: Translator) -> AnyPublisher<File, Error> in
        translator.open(flags: O_RDONLY)
      }
      .flatMap { (file: File) -> AnyPublisher<DispatchData, Error> in
        fileBox.file = file
        return fileBox.file!.read(max: SSIZE_MAX)
      }
      .sink(receiveCompletion: { completion in
        fileBox.file = nil
        switch completion {
        case .finished:
          expectation.fulfill()
        case .failure(let error as LocalFileError):
          XCTFail(error.msg)
        case .failure(let error):
          XCTFail("Unknown error \(error)")
        }
      },
      receiveValue: { data in
        XCTAssertEqual(Data(data), self.sourceData)
      }).store(in: &cancellableBag)
    
    waitForExpectations(timeout: 15, handler: nil)
    
    // TODO close file
    //file.close()
  }
  
  func testFileWriteTo() throws {
    self.continueAfterFailure = false
    // For SFTP it will be useful to have the channel reachable, and then stop it through a timer to test the reconnect.
    let f = Local()
    let expectation = self.expectation(description: "Buffer Complete")
    let buffer = MemoryBuffer(fast: true)
    let fileBox = FileBox()
    
    // TODO Explicitely close the file or do it once it gets
    // dumped.
    f.walkTo(sourceFile.path)
      .flatMap { (translator: Translator) -> AnyPublisher<File, Error> in
        translator.open(flags: O_RDONLY)
      }
      .flatMap { (file: File) -> AnyPublisher<Int, Error> in
        fileBox.file = file
        return (fileBox.file! as! WriterTo).writeTo(buffer)
      }
      .sink(receiveCompletion: { completion in
        fileBox.file = nil
        switch completion {
        case .finished:
          XCTAssertEqual(buffer.count, self.sourceData.count, "Data copied does not match.")
          expectation.fulfill()
        case .failure(let error as LocalFileError):
          XCTFail(error.msg)
        case .failure(let error):
          XCTFail("Unknown error \(error)")
        }
      },
      receiveValue: { wroteBytes in
        print(wroteBytes)
        XCTAssertFalse(wroteBytes <= 0, "Nothing received")
      }).store(in: &cancellableBag)
    
    waitForExpectations(timeout: 15, handler: nil)
  }
  
  // WriteToWriter
  // Hash check for result
  func testFileWriteToWriter() throws {
    self.continueAfterFailure = false
    // For SFTP it will be useful to have the channel reachable, and then stop it through a timer to test the reconnect.
    let f = Local()
    let dst = f.clone()
    let expectation = self.expectation(description: "Buffer Complete")
    var written = 0
    let sourceBox = FileBox()
    let destinationBox = FileBox()
    // TODO Explicitely close the file or do it once it gets
    // dumped.
    f.walkTo(sourceFile.path)
      .flatMap { (translator: Translator) -> AnyPublisher<File, Error> in
        translator.open(flags: O_RDONLY)
      }
      .flatMap { srcFile -> AnyPublisher<Int, Error> in
        sourceBox.file = srcFile
        return dst.walkTo(self.fixtureRoot.path)
          .flatMap { $0.create(name: "copy.bin", mode: 0o644) }
          .flatMap { dstFile in
            destinationBox.file = dstFile
            return (sourceBox.file! as! WriterTo).writeTo(destinationBox.file!)
          }.eraseToAnyPublisher()
      }.sink(receiveCompletion: { completion in
        sourceBox.file = nil
        destinationBox.file = nil
        switch completion {
        case .finished:
          XCTAssertEqual(written, self.sourceData.count, "Data copied does not match.")
          let copied = self.fixtureRoot.appendingPathComponent("copy.bin")
          XCTAssertEqual(try? Data(contentsOf: copied), self.sourceData)
          expectation.fulfill()
        case .failure(let error as LocalFileError):
          XCTFail(error.msg)
        case .failure(let error):
          XCTFail("Unknown error \(error)")
        }
      },
      receiveValue: { wroteBytes in
        written += wroteBytes
        print("Written \(written)")
        XCTAssertFalse(wroteBytes <= 0, "Nothing received")
      }).store(in: &cancellableBag)
    
    waitForExpectations(timeout: 1500, handler: nil)
  }
  
  func testWstat() throws {
    let f = Local()
    let expectation = self.expectation(description: "Buffer Complete")
    let renamedFile = fixtureRoot.appendingPathComponent("renamed.txt")
    
    f.walkTo(sourceFile.path)
      .flatMap { file -> AnyPublisher<Bool, Error> in
        let attrs: [FileAttributeKey:Any] = [.name: renamedFile.path,
                                             .modificationDate: NSDate(timeIntervalSinceNow: -40000)]
        return file.wstat(attrs)
      }.sink(receiveCompletion: { completion in
        switch completion {
        case .finished:
          XCTAssertTrue(FileManager.default.fileExists(atPath: renamedFile.path))
          expectation.fulfill()
        case .failure(let error as LocalFileError):
          XCTFail(error.msg)
        case .failure(let error):
          XCTFail("Unknown error \(error)")
        }
      },
      receiveValue: { XCTAssertTrue($0) }).store(in: &cancellableBag)
    
    waitForExpectations(timeout: 2, handler: nil)
  }
}

class MemoryBuffer: Writer {
  var count = 0
  let fast: Bool
  let queue: DispatchQueue
  
  init(fast: Bool) {
    self.fast = fast
    self.queue = DispatchQueue(label: "test")
  }
  
  func write(_ buf: DispatchData, max length: Int) -> AnyPublisher<Int, Error> {
    return Just(buf.count).print("Write Request").receive(on: self.queue).map { val in
      self.count += buf.count
      
      if !self.fast {
        //sleep(1)
        usleep(1000)
      }
      print("==== Wrote \(self.count)")
      return val
    }.mapError { $0 as Error }.eraseToAnyPublisher()
  }
}
