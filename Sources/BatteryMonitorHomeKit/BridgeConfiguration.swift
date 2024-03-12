//
//  BridgeConfiguration.swift
//  
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation

public struct BridgeConfiguration: Equatable, Hashable, Codable, Sendable {
    
    public var name: String
    
    public var serialNumber: String
    
    public var model: String
    
    public var manufacturer: String
    
    public var timeout: UInt
    
    public var accessories: [Accessory]
    
    public init(
        name: String = "Battery Monitor Bridge",
        accessories: [Accessory] = [],
        timeout: UInt = 60 * 5,
        serialNumber: String = UUID().uuidString,
        model: String = "Bridge",
        manufacturer: String = "Miller Technology"
    ) {
        self.name = name
        self.accessories = accessories
        self.timeout = timeout
        self.serialNumber = serialNumber
        self.model = model
        self.manufacturer = manufacturer
    }
}

public extension BridgeConfiguration {
    
    struct Accessory: Equatable, Hashable, Codable, Sendable {
        
        /// Unique identifier for the sensor. Can be name or Bluetooth address.
        public let id: String
        
        public var name: String?
        
        public var model: String?
    }
}
