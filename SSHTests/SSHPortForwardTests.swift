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
import Dispatch
import Network

@testable import SSH

private final class FixtureHTTPServer {
  private let queue = DispatchQueue(label: "FixtureHTTPServer")
  private var listener: NWListener?
  private let payload = Data("fixture-ok".utf8)

  func start(test: XCTestCase) throws -> UInt16 {
    let listener = try NWListener(using: .tcp, on: .any)
    self.listener = listener

    let ready = test.expectation(description: "Fixture HTTP server ready")
    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        ready.fulfill()
      case .failed(let error):
        XCTFail("Fixture HTTP server failed: \(error)")
        ready.fulfill()
      default:
        break
      }
    }

    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection)
    }
    listener.start(queue: queue)

    test.wait(for: [ready], timeout: 5)
    guard let port = listener.port?.rawValue else {
      throw NSError(
        domain: "SSHPortForwardTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Fixture HTTP server did not expose a port."]
      )
    }
    return port
  }

  func stop() {
    listener?.cancel()
    listener = nil
  }

  private func handle(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [payload] _, _, _, _ in
      var response = Data("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: \(payload.count)\r\n\r\n".utf8)
      response.append(payload)
      connection.send(content: response, completion: .contentProcessed { _ in
        connection.cancel()
      })
    }
  }
}

extension SSHTests {
  private func portUInt16(_ value: Int, name: String) -> UInt16 {
    guard let converted = UInt16(exactly: value) else {
      XCTFail("Invalid \(name) value: \(value)")
      return 0
    }
    return converted
  }

  private func assertForwardedSSHBanner(on localPort: Int, label: String) {
    guard let nwPort = NWEndpoint.Port(rawValue: UInt16(localPort)) else {
      XCTFail("Invalid forwarded local port: \(localPort)")
      return
    }

    let expectation = self.expectation(description: "SSH banner received (\(label))")
    let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)

    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.receive(minimumIncompleteLength: 4, maximumLength: 128) { data, _, _, error in
          if let error = error {
            XCTFail("Forwarded connection failed (\(label)): \(error)")
            expectation.fulfill()
            return
          }

          guard let data = data, !data.isEmpty else {
            XCTFail("No banner received through forwarded port (\(label)).")
            expectation.fulfill()
            return
          }

          let banner = String(data: data, encoding: .utf8) ?? ""
          XCTAssertTrue(banner.contains("SSH-"), "Unexpected forwarded banner (\(label)): \(banner)")
          expectation.fulfill()
        }
      case .failed(let error):
        XCTFail("Forwarded connection setup failed (\(label)): \(error)")
        expectation.fulfill()
      default:
        break
      }
    }

    connection.start(queue: DispatchQueue.global(qos: .userInitiated))
    wait(for: [expectation], timeout: 10)
    connection.cancel()
  }

  func testForwardPort() throws {
    let expectConnection = self.expectation(description: "Connected")
    let expectListenerClosed = self.expectation(description: "Listener Closed")
    
    var connection: SSHClient?
    var lis: SSHPortForwardListener?
    let localPort = Credentials.portForwardLocalPort
    let localPortUInt16 = portUInt16(localPort, name: "local forward port")
    let destinationPortUInt16 = portUInt16(Credentials.portForwardDestinationPort, name: "forward destination port")
    
    SSHClient
      .dialWithTestConfig()
      .map() { conn -> SSHPortForwardListener in
        print("Received Connection")
        connection = conn
        
        lis = SSHPortForwardListener(
          on: localPortUInt16,
          toDestination: Credentials.portForwardDestinationHost,
          on: destinationPortUInt16,
          using: conn
        )
        
        return lis!
      }
      .flatMap { $0.connect() }
      .sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            expectListenerClosed.fulfill()
          case .failure(let error):
            XCTFail("\(error)")
          }
        },
        receiveValue: { event in
          switch event {
          case .starting:
            print("Listener Starting")
          case .ready:
            expectConnection.fulfill()
          case .error(let error):
            XCTFail("\(error)")
          default:
            break
          }
        }).store(in: &cancellableBag)
    
    wait(for: [expectConnection], timeout: 15)

    assertForwardedSSHBanner(on: localPort, label: "first")
    assertForwardedSSHBanner(on: localPort, label: "second")
    assertForwardedSSHBanner(on: localPort, label: "third")

    XCTAssertTrue((lis?.connections.count ?? 0) >= 1, "No forwarded streams were established.")
    
    // Close the Tunnel and all open connections.
    lis!.close()
    wait(for: [expectListenerClosed], timeout: 5)
  }
  
  func testListenerPort() throws {
    self.continueAfterFailure = false
    
    var expectConnection = self.expectation(description: "Connected")
    
    var connection: SSHClient?
    var lis: SSHPortForwardListener?
    let localPort = Credentials.portForwardLocalPort
    let localPortUInt16 = portUInt16(localPort, name: "local forward port")
    let destinationPortUInt16 = portUInt16(Credentials.portForwardDestinationPort, name: "forward destination port")
    
    SSHClient.dialWithTestConfig()
      .tryMap() { conn -> SSHPortForwardListener in
        print("Received Connection")
        connection = conn
        
        lis = SSHPortForwardListener(
          on: localPortUInt16,
          toDestination: Credentials.portForwardDestinationHost,
          on: destinationPortUInt16,
          using: conn
        )
        
        return lis!
      }.flatMap { $0.connect() }
      .compactMap { event -> AnyPublisher<Void, Error>? in
        switch event {
        case .starting:
          print("Listener Starting")
          return nil
        case .ready:
          print("Listener Ready")
          expectConnection.fulfill()
          return nil
        default:
          return nil
        }
      }.assertNoFailure()
      .sink {_ in }.store(in: &cancellableBag)
    
    wait(for: [expectConnection], timeout: 15)
    
    // A second listener should fail when started on same port.
    let expectFailure = self.expectation(description: "Connected")
    
    let lis2 = SSHPortForwardListener(
      on: localPortUInt16,
      toDestination: Credentials.portForwardDestinationHost,
      on: destinationPortUInt16,
      using: connection!
    )
    lis2.connect().tryMap { event in
      print("Listener sent \(event)")
    }.sink (receiveCompletion: {completion in
      switch completion {
      case .failure(let error):
        print("\(error)")
        expectFailure.fulfill()
      case .finished:
        XCTFail("Listener should not have started")
      }
    }, receiveValue: {}).store(in: &cancellableBag)
    
    wait(for: [expectFailure], timeout: 15)
    
  }
  
  func testReverseForwardPort() throws {
    // We test it by doing the same as the forward, but on the other side.
    // So instead of a URLRequest, execute a command on the "server"
    // calling the routed port.
    // curl -o /dev/null -s -w "%{http_code}\n" http://localhost
    self.continueAfterFailure = false
    
    let expectForward = self.expectation(description: "Forward ready")
    let expectStream = self.expectation(description: "Stream received")
    
    var connection: SSHClient?
    
    var client: SSHPortForwardClient?
    let helperServer = FixtureHTTPServer()
    let helperPort = try helperServer.start(test: self)
    let remoteForwardPort = Credentials.reverseForwardRemotePort
    let remoteForwardPortUInt16 = portUInt16(remoteForwardPort, name: "reverse forward remote port")
    
    SSHClient.dial(Credentials.password.host, with: .testConfig)
      .tryMap() { conn -> SSHPortForwardClient in
        print("Received Connection")
        connection = conn
        
        client = SSHPortForwardClient(
          forward: Credentials.reverseForwardTargetHost,
          onPort: helperPort,
          toRemotePort: remoteForwardPortUInt16,
          using: conn
        )
        return client!
      }.flatMap { c -> AnyPublisher<Void, Error> in
        expectForward.fulfill()
        return c.ready()
      }.flatMap { client!.connect() }
      .assertNoFailure()
      .sink { event in
        print("Received \(event)")
        switch event {
        case .ready:
          break
        case .error(let error):
          XCTFail("\(error)")
        default:
          break
        }
      }.store(in: &cancellableBag)
    
    wait(for: [expectForward], timeout: 15)
    
    var cmd: SSH.Stream?
    let curl = "curl -o /dev/null -s -w \"%{http_code}\\n\" localhost:\(remoteForwardPort)"
    let cancelRequest = connection!.requestExec(command: curl)
      .flatMap { stream -> AnyPublisher<DispatchData, Error> in
        cmd = stream
        return stream.read(max: SSIZE_MAX)
      }
      .assertNoFailure()
      .sink { buf in
        let output = String(data: buf as AnyObject as! Data, encoding: .utf8)
        // Output may be 000 in case the channel did not succeed.
        XCTAssertEqual(output?.trimmingCharacters(in: .whitespacesAndNewlines), "200")
        expectStream.fulfill()
      }
    wait(for: [expectStream], timeout: 15)
    
    // Closing up stuff. Sometimes there may be a callback or error of some kind because we got rid of some object.
    client!.close()
    helperServer.stop()
  }
  
  func testProxyCommand() throws {
    // Connect to the proxy on the exposed port.
    let configProxy = SSHClientConfig(user: Credentials.none.user,
                                      port: Credentials.port,
                                      authMethods: [])
    
    // The proxy connects to itself on default port, so this should go through.
    let config = SSHClientConfig(user: Credentials.none.user,
                                 proxyJump: "\(Credentials.none.host):\(Credentials.port)",
                                 //proxyCommand: "ssh -W %h:%p localhost",
                                 authMethods: [])
    
    let expectConnection = self.expectation(description: "Connected")
    let expectExecFinished = self.expectation(description: "Exec finished")
    let expectConnClosed = self.expectation(description: "Main connection closing the proxy")
    let expectThreadExit = self.expectation(description: "Exit thread")
    // The callback could be async scheduled, because it will anyway have to
    // figure out things with the socket. But we have to retain it somehow.
    var proxyCancellable: AnyCancellable?
    let execProxyCommand: SSHClient.ExecProxyCommandCallback = { (command, sockIn, sockOut) in
      // Needs to start a tunnel to the destination, which
      // should be specified at the command.
      // The tunnel is then mapped to the socket.
      // If running a command, we would just map stdio and run the command.
      let t = Thread(block: {
        // We should be parsing the command, but assume it is ok
        let destination = Credentials.none.host
        let destinationPort = Int32(Credentials.port) ?? 22
        var stream: SSH.Stream?
        
        let output = DispatchOutputStream(stream: sockOut)
        let input = DispatchInputStream(stream: sockIn)
        var connection: SSHClient?
        
        proxyCancellable = SSHClient.dial(Credentials.none.host, with: configProxy)
          .flatMap() { conn -> AnyPublisher<SSH.Stream, Error> in
            connection = conn
            return conn.requestForward(to: destination, port: destinationPort, from: "localhost", localPort: 22)
          }.sink(receiveCompletion: { completion in
            switch completion {
            case .finished:
              break
            case .failure(let error as SSHError):
              XCTFail(error.description)
            // Closing the socket should also close the other connection
            case .failure(let error):
              XCTFail("Unknown error - \(error)")
            }
          }, receiveValue: { s in
            stream = s
            s.handleCompletion = {
              expectConnClosed.fulfill()
            }
            // Uncomment if you want to delay the other connection.
            // Interesting to see how the other one will just try again the Connect.
            //RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
            s.connect(stdout: output, stdin: input)
          })
        self.wait(for: [expectExecFinished], timeout: 10)
        
        // Now we await here for the main connection to close.
        // Closing the main connection should close the proxy as well.
        self.wait(for: [expectConnClosed], timeout: 5)
        
        expectThreadExit.fulfill()
      })
      t.start()
    }
    
    var connection: SSHClient?
    
    let testCommand = "echo hello"
    var output: DispatchData?
    var cancellable = SSHClient.dial(Credentials.none.host, with: config, withProxy: execProxyCommand)
      .flatMap() { conn -> AnyPublisher<SSH.Stream, Error> in
        connection = conn
        return conn.requestExec(command: testCommand)
      }
      .flatMap {
        $0.read(max: 6)
      }
      .sink(receiveCompletion: { completion in
        switch completion {
        case .finished:
          expectConnection.fulfill()
        case .failure(let error as SSHError):
          XCTFail(error.description)
        case .failure(let error):
          XCTFail("Unknown error - \(error)")
        }
        
      }, receiveValue: { buf in
        output = buf
      })
    
    wait(for: [expectConnection], timeout: 15)
    expectExecFinished.fulfill()
    
    // Properly wrapping things up, simulating what an app would do.
    // Just closing the main connection should close the proxy.
    connection = nil
    wait(for: [expectThreadExit], timeout: 15)
    
    XCTAssertTrue(output?.count == 6, "Not received all bytes for 'hello\n'")
  }
  
  func testProxyCommandConnFailure() throws {
    // The proxy will not be able to authenticate, and this should trigger
    // an error during connection, because we won't be able to establish it.
    var config = SSHClientConfig(user: "carlos",
                                 proxyJump: Credentials.none.host,
                                 //proxyCommand: "ssh -W %h:%p localhost",
                                 authMethods: [AuthPassword(with: "")])
    
    let expectFailure = self.expectation(description: "Connection should fail")
    // The callback could be async scheduled, because it will anyway have to
    // figure out things with the socket. But we have to retain it somehow.
    var proxyCancellable: AnyCancellable?
    let execProxyCommand: SSHClient.ExecProxyCommandCallback = { (command, sockIn, sockOut) in
      let t = Thread(block: {
        // Wait and close the socket. Note that if a connection
        // fails, that is what a CLI would do.
        
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        close(sockIn)
        close(sockOut)
      })
      t.start()
    }
    
    var connection: SSHClient?
    
    var cancellable = SSHClient.dial(Credentials.none.host,
                                     with: config, withProxy: execProxyCommand)
      .sink(receiveCompletion: { completion in
        switch completion {
        case .finished:
          XCTFail("Connection should not have succeeded with no proxy socket")
        case .failure(let error as SSHError):
          print("Correctly received error: \(error)")
          expectFailure.fulfill()
        case .failure(let error):
          XCTFail("Unknown error - \(error)")
        }
        
      }, receiveValue: { _ in })
    
    wait(for: [expectFailure], timeout: 500)
  }
  
  // TODO Come back to this after adding TCP Keep Alive packets
  // The other side of the stream will be happy to think everything works
  // when the other side is idle.
  // https://blog.stephencleary.com/2009/05/detection-of-half-open-dropped.html
  // https://stackoverflow.com/questions/34615807/nsstream-delegate-not-firing-errors
  func testProxyCommandStreamFailure() throws {
    throw XCTSkip("Suspect issue with NSInputStream. Not receiving EOF events.")
    // Killing the proxy should close the connection, and if handling
    // the stream properly, it should be closed as well. And that in a
    // chain should make everything else receive a close as well, probably
    // at the session level.
    // This test may be necessary to see how the flow of errors would work.
    let config = SSHClientConfig(user: Credentials.regularUser,
                                 port: Credentials.port,
                                 proxyJump: Credentials.none.host,
                                 proxyCommand: "ssh -W %h:%p localhost",
                                 authMethods: [AuthPassword(with: Credentials.regularUserPassword)],
                                 loggingVerbosity: .debug)
    
    let destination = Credentials.none.host
    let destinationPort = Int32(Credentials.port) ?? 22
    let configProxy = SSHClientConfig.testConfig
    
    let expectConnection = self.expectation(description: "Connected")
    let expectExecFinished = self.expectation(description: "Exec finished")
    let expectConnFailure = self.expectation(description: "Main connection received failure")
    let expectThreadExit = self.expectation(description: "Exit thread")
    let expectEOF = self.expectation(description: "EOF")
    
    var proxyCancellable: AnyCancellable?
    let execProxyCommand: SSHClient.ExecProxyCommandCallback = { (command, sockIn, sockOut) in
      // Needs to start a tunnel to the destination, which
      // should be specified at the command.
      // The tunnel is then mapped to the socket.
      // If running a command, we would just map stdio and run the command.
      let t = Thread(block: {
        var stream: SSH.Stream?
        
        var output: DispatchOutputStream? = DispatchOutputStream(stream: dup(sockOut))
        var input: DispatchInputStream? = DispatchInputStream(stream: dup(sockIn))
        var connection: SSHClient?
        
        proxyCancellable = SSHClient.dial(destination, with: configProxy)
          .flatMap() { conn -> AnyPublisher<SSH.Stream, Error> in
            connection = conn
            return conn.requestForward(to: destination, port: destinationPort, from: destination, localPort: 22)
          }.sink(receiveCompletion: { completion in
            switch completion {
            case .finished:
              break
            case .failure(let error as SSHError):
              XCTFail(error.description)
            // Closing the socket should also close the other connection
            case .failure(let error):
              XCTFail("Unknown error - \(error)")
            }
          }, receiveValue: { s in
            stream = s
            s.handleCompletion = {
              print("Complete")
            }
            s.handleFailure = { error in
              print("Failed")
            }
            s.connect(stdout: output!, stdin: input!)
          })
        
        self.wait(for: [expectExecFinished], timeout: 5)
        
        connection?.rloop.run(until: Date(timeIntervalSinceNow: 2))
        //                output?.close()
        //                input?.close()
        
        // Close the channel
        stream?.cancel()
        stream?.sendEOF().assertNoFailure().sink { _ in
          expectEOF.fulfill()
        }
        .store(in: &self.cancellableBag)
        //
        self.wait(for: [expectEOF], timeout: 500)
        stream?.cancel()
        stream = nil
        connection = nil
        
        close(sockIn)
        close(sockOut)
        self.wait(for: [expectConnFailure], timeout: 500)
        
        //expectThreadExit.fulfill()
      })
      t.start()
    }
    
    var connection: SSHClient?
    
    let testCommand = "du /"
    var output: DispatchData?
    var stream: SSH.Stream?
    let buffer = MemoryBuffer(fast: true)
    
    var cancellable = SSHClient.dial(Credentials.none.host, with: config, withProxy: execProxyCommand)
      .flatMap() { conn -> AnyPublisher<SSH.Stream, Error> in
        connection = conn
        return conn.requestExec(command: testCommand)
      }.assertNoFailure()
      .sink { s in
        stream = s
        s.handleFailure = { error in
          print("Captured error on Main SSH \(error)")
          expectConnFailure.fulfill()
        }
        s.handleCompletion = {
          print("Main connection Completed")
        }
        expectExecFinished.fulfill()
        // We expect this will not return, but want to capture an error
        s.connect(stdout: buffer)
      }
    
    wait(for: [expectThreadExit], timeout: 500)
  }
}
