//
//  Accessory.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT

/// Battery Monitor Accessory
protocol BatteryMonitorAccessory: AnyObject {
    
    associatedtype Advertisement: BatteryMonitorAdvertisement
        
    var peripheral: NativeCentral.Peripheral { get }
    
    var central: NativeCentral { get }
    
    var advertisement: Advertisement { get }
    
    init(
        peripheral: NativeCentral.Peripheral,
        central: NativeCentral,
        advertisement: Advertisement,
        configuration: BridgeConfiguration.Accessory?
    )
}

extension BatteryMonitorAccessory {
    
    static var accessoryType: BatteryMonitorAccessoryType { Advertisement.accessoryType }
}

/// Battery Monitor Accessory Type
public enum BatteryMonitorAccessoryType: String, Codable, Sendable, CaseIterable {
    
    case bt20 = "BT20"
    case tb6000Pro = "TB6000Pro"
    case bm2 = "BM2"
    case powerWatchdog = "PowerWatchdog"
}

// MARK: - GATT

internal extension BatteryMonitorAccessory {
    
    @discardableResult
    func connect() async throws -> GATTConnection<NativeCentral> {
        let central = self.central
        let peripheral = self.peripheral
        let stream = try await central.scan(filterDuplicates: false)
        for try await scanData in stream {
            guard scanData.peripheral == peripheral else {
                continue
            }
            stream.stop()
            break
        }
        if await central.peripherals[peripheral] == false {
            print("[\(peripheral)]: Connecting...")
            // initiate connection
            try await central.connect(to: peripheral)
        }
        // cache MTU
        let maximumTransmissionUnit = try await central.maximumTransmissionUnit(for: peripheral)
        // get characteristics by UUID
        let servicesCache = try await central.cacheServices(for: peripheral)
        let connectionCache = GATTConnection(
            central: central,
            peripheral: peripheral,
            maximumTransmissionUnit: maximumTransmissionUnit,
            cache: servicesCache
        )
        // store connection cache
        return connectionCache
    }
}
