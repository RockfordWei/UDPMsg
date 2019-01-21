import Foundation
import Dispatch

public class UDPMsg {

  enum Exception: Error {
    case unableToBind
    case unableToAllocate
  }

  private let listener: Int32
  private var live = true
  private var queue: DispatchQueue?
  private let lock = DispatchSemaphore.init(value: 1)
  private let bufferSize = 4096
  private let buffer: UnsafeMutableRawPointer

  /// Setup a UDP
  /// - parameter port: if greater then 0, then it will setup a local udp server and bind to that port; 0 means udp client only.
  /// - throws: Exception
  public init(port: Int = 0) throws {
    #if os(Linux)
    listener = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
    #else
    listener = socket(AF_INET, SOCK_DGRAM, 0)
    #endif
    if port > 0 {
      var opt: Int32 = 1
      setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout.size(ofValue: opt)))
      let host = UDPMsg.setupAddress(port: port)
      var address = UDPMsg.convert(address: host)
      guard 0 == bind(listener, &address, socklen_t(MemoryLayout<sockaddr_in>.size)) else {
        throw Exception.unableToBind
      }
      queue = DispatchQueue.init(label: "UDPMsg\(port)")
    } else {
      queue = nil
    }
    guard let buf = malloc(bufferSize) else {
      throw Exception.unableToAllocate
    }
    buffer = buf
  }

  /// terminate the udp server if running
  public func terminate() {
    live = false
  }

  deinit {
    live = false
    free(self.buffer)
    close(listener)
  }

  /// setup a socket address by the domain name and port
  /// - parameter domain: domain name of the objective host
  /// - parameter port: port number of the objective host
  /// - returns: sock address if the domain and port are valid
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

  /// setup a socket address by the domain name and port
  /// - parameter ip: ip address of the objective host
  /// - parameter port: port number of the objective host
  /// - returns: sock address
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

  /// convert an address from sockaddr_in to sockaddr
  public static func convert(address: sockaddr_in) -> sockaddr {
    var from = address
    var to = sockaddr()
    memcpy(&to, &from, MemoryLayout<sockaddr_in>.size)
    return to
  }

  /// convert an address from sockaddr to sockaddr_in
  public static func cast(address: sockaddr) -> sockaddr_in {
    var from = address
    var to = sockaddr_in()
    memcpy(&to, &from, MemoryLayout<sockaddr_in>.size)
    return to
  }

  /// send a udp packet
  /// - parameter to: address to deliver
  /// - parameter data: content to deliver
  /// - returns: size of the packet
  public func send(to: sockaddr_in, with: Data) -> Int {
    var addr = sockaddr()
    var pto = to
    memcpy(&addr, &pto, MemoryLayout.size(ofValue: to))
    return self.send(to: addr, with: with)
  }

  /// send a udp packet
  /// - parameter to: address to deliver
  /// - parameter data: content to deliver
  /// - returns: size of the packet
  public func send(to: sockaddr, with: Data) -> Int {
    return UDPMsg.send(by: self.listener, to: to, with: with)
  }

  /// send a udp packet
  /// - parameter by: a socket number used to send data
  /// - parameter to: address to deliver
  /// - parameter data: content to deliver
  /// - returns: size of the packet
  public static func send(by: Int32, to: sockaddr, with: Data) -> Int {
    return with.withUnsafeBytes{ (pointer: UnsafePointer<UInt8>) -> Int in
      var addr = to
      return sendto(by, pointer, with.count, 0, &addr, socklen_t(MemoryLayout.size(ofValue: to)))
    }
  }

  /// run a UDP server
  /// - parameter callback: a closure to call when a udp message arrived
  /// - throws: Exception
  public func run(callback: @escaping (UDPMsg, Data, sockaddr_in) -> ()) throws {
    guard let q = self.queue else {
      throw Exception.unableToBind
    }
    self.live = true
    q.async {
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
