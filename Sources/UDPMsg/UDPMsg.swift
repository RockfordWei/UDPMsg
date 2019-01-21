import Foundation
import Dispatch

public class UDPMsg {

  enum Exception: Error {
    case unableToBind
    case unableToAllocate
  }

  private let listener: Int32
  private var live = true
  private var queue: DispatchQueue
  private let lock = DispatchSemaphore.init(value: 1)
  private let bufferSize = 4096
  private let buffer: UnsafeMutableRawPointer
  public init(port: Int = 6379) throws {
    #if os(Linux)
    listener = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
    #else
    listener = socket(AF_INET, SOCK_DGRAM, 0)
    #endif
    var opt: Int32 = 1
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout.size(ofValue: opt)))
    let host = UDPMsg.setupAddress(port: port)
    var address = UDPMsg.convert(address: host)
    guard 0 == bind(listener, &address, socklen_t(MemoryLayout<sockaddr_in>.size)) else {
      throw Exception.unableToBind
    }
    guard let buf = malloc(bufferSize) else {
      throw Exception.unableToAllocate
    }
    buffer = buf
    queue = DispatchQueue.init(label: "UDPMsg\(port)")
  }

  public func terminate() {
    live = false
  }

  deinit {
    live = false
    free(self.buffer)
  }

  public static func setupAddress(domain: String, port: Int) -> sockaddr_in? {
    guard let host = gethostbyname(domain)?.pointee,
      let first = host.h_addr_list.pointee,
      let pbuf = malloc(32) else { return nil }

    memset(pbuf, 0, 32)
    defer {
      free(pbuf)
    }
    guard let ip = inet_ntop(host.h_addrtype, first, pbuf.assumingMemoryBound(to: CChar.self), 32) else {
      return nil
    }
    let sip = String.init(cString: ip)
    #if DEBUG
    print("domain: ", domain, "ip: ", sip)
    #endif
    return setupAddress(ip: sip, port: port)
  }

  public static func setupAddress(ip: String = "0.0.0.0", port: Int) -> sockaddr_in {
    let ipAddr = inet_addr(ip)
    let lo = UInt16(port & 0x00FF) << 8
    let hi = UInt16(port & 0xFF00) >> 8
    var host = sockaddr_in.init()
    host.sin_family = sa_family_t(AF_INET)
    host.sin_addr.s_addr = ipAddr
    host.sin_port = lo | hi
    return host
  }

  public static func convert(address: sockaddr_in) -> sockaddr {
    var from = address
    var to = sockaddr()
    memcpy(&to, &from, MemoryLayout<sockaddr_in>.size)
    return to
  }

  public static func cast(address: sockaddr) -> sockaddr_in {
    var from = address
    var to = sockaddr_in()
    memcpy(&to, &from, MemoryLayout<sockaddr_in>.size)
    return to
  }

  public func send(to: sockaddr_in, with: Data) -> Int {
    var addr = sockaddr()
    var pto = to
    memcpy(&addr, &pto, MemoryLayout.size(ofValue: to))
    return self.send(to: addr, with: with)
  }

  public func send(to: sockaddr, with: Data) -> Int {
    return UDPMsg.send(by: self.listener, to: to, with: with)
  }

  public static func send(by: Int32, to: sockaddr, with: Data) -> Int {
    return with.withUnsafeBytes{ (pointer: UnsafePointer<UInt8>) -> Int in
      var addr = to
      return sendto(by, pointer, with.count, 0, &addr, socklen_t(MemoryLayout.size(ofValue: to)))
    }
  }

  public func run(callback: @escaping (UDPMsg, Data, sockaddr_in) -> ()) throws {
    queue.async {
      while self.live {
        self.lock.wait()
        var host = sockaddr()
        var size: UInt32 = 0
        let r = recvfrom(self.listener, self.buffer, self.bufferSize, 0, &host, &size)
        if r > 0 && size <= MemoryLayout<sockaddr_in>.size {
          let data = Data.init(bytes: self.buffer, count: r)
          let address = UDPMsg.cast(address: host)
          callback(self, data, address)
        }
        self.lock.signal()
      }
    }
  }
}
