//
//  Storage.swift
//  
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import HAP

public struct HAPConfiguration: Equatable, Hashable, Codable, Sendable {
    
    public let name: String
    
    public var serialNumber: String
    
    public var model: String
    
    public var manufacturer: String
    
    public var accessories: [BridgeConfiguration.Accessory]
    
    public var timeout: UInt
    
    internal var homeKit: HomeKit?
}

public extension HAPConfiguration {
    
    init() {
        self.init(BridgeConfiguration())
    }
    
    init(_ configuration: BridgeConfiguration) {
        self.init(
            name: configuration.name,
            serialNumber: configuration.serialNumber,
            model: configuration.model,
            manufacturer: configuration.manufacturer,
            accessories: configuration.accessories,
            timeout: configuration.timeout
        )
    }
}

public extension BridgeConfiguration {
    
    init(_ configuration: HAPConfiguration) {
        self.init(
            name: configuration.name,
            accessories: configuration.accessories,
            timeout: configuration.timeout,
            serialNumber: configuration.serialNumber,
            model: configuration.model,
            manufacturer: configuration.manufacturer
        )
    }
}

public extension HAPConfiguration {
    
    struct HomeKit: Equatable, Hashable, Codable, Sendable {
        
        public let identifier: String
        
        public var setupCode: String
        
        public var setupKey: String
        
        public var stableHash: Int
        
        public var privateKey: Data
        
        public var number: UInt32
        
        public var aidForAccessorySerialNumber = [String: InstanceID]()
        
        public var aidGenerator = AIDGenerator()
        
        public var pairings: [PairingIdentifier: Pairing] = [:]
    }
}

public extension HAPConfiguration.HomeKit {
    
    typealias InstanceID = Int
    
    typealias PairingIdentifier = Data
    
    typealias PublicKey = Data
    
    struct Pairing: Codable, Equatable, Hashable, Sendable {
        
        public enum Role: UInt8, Codable, Sendable {
            case regularUser = 0x00
            case admin = 0x01
        }

        // iOS Device's Pairing Identifier, iOSDevicePairingID
        public let identifier: PairingIdentifier

        // iOS Device's Curve25519 public key
        public let publicKey: PublicKey

        public var role: Role
    }
    
    struct AIDGenerator: Codable, Equatable, Hashable, Sendable {
        public var lastAID: InstanceID = 1
    }
}

final class ConfigurationHAPStorage: Storage {
    
    private let encoder = JSONEncoder()
    
    private let decoder = JSONDecoder()
    
    private let fileManager = FileManager()
    
    let filename: String
    
    init(filename: String) {
        self.filename = filename
    }
    
    func readConfiguration() throws -> HAPConfiguration {
        let url = URL(fileURLWithPath: filename)
        let jsonData = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try decoder.decode(HAPConfiguration.self, from: jsonData)
    }
    
    func read() throws -> Data {
        let configuration = try readConfiguration()
        guard let homeKit = configuration.homeKit else {
            throw CocoaError(.coderValueNotFound)
        }
        return try encoder.encode(homeKit)
    }
    
    func writeConfiguration(_ newValue: HAPConfiguration) throws {
        let jsonData = try encoder.encode(newValue)
        if fileManager.fileExists(atPath: filename) {
            try jsonData.write(to: URL(fileURLWithPath: filename), options: [.atomic])
        } else {
            fileManager.createFile(atPath: filename, contents: jsonData)
        }
    }
    
    func write(_ data: Data) throws {
        var configuration: HAPConfiguration
        if fileManager.fileExists(atPath: filename) {
            configuration = try readConfiguration()
        } else {
            configuration = HAPConfiguration(BridgeConfiguration())
        }
        configuration.homeKit = try decoder.decode(HAPConfiguration.HomeKit.self, from: data)
        try writeConfiguration(configuration)
    }
}
