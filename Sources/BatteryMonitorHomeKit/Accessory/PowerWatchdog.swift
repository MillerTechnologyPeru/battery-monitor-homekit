//
//  PowerWatchdog.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT
import HAP
import HughesAutoformers

final class PowerWatchdogAccessory: HAP.Accessory.ContactSensor, BatteryMonitorAccessory {
    
    static var accessoryType: BatteryMonitorAccessoryType { .powerWatchdog }
    
    let peripheral: NativeCentral.Peripheral
    
    let central: NativeCentral
    
    let configuration: BridgeConfiguration.Accessory?
    
    let advertisement: PowerWatchdog
    
    let surgeProtector = SurgeProtectorService(line: 0)
    
    init(
        peripheral: NativeCentral.Peripheral,
        central: NativeCentral,
        advertisement: PowerWatchdog,
        configuration: BridgeConfiguration.Accessory?
    ) {
        self.peripheral = peripheral
        self.central = central
        self.advertisement = advertisement
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "Power Watchdog Surge Protector",
            serialNumber: advertisement.id.description,
            manufacturer: "Hughes Autoformers",
            model: configuration?.model ?? Swift.type(of: advertisement).accessoryType.rawValue,
            firmwareRevision: "1.0.0"
        )
        super.init(
            info: info,
            additionalServices: [
                surgeProtector
            ]
        )
        start()
        //self.bridgeState.accessoryIdentifier.value = advertisement.address.rawValue
    }
}

private extension PowerWatchdogAccessory {
    
    func start() {
        let peripheral = self.peripheral
        Task { [weak self] in
            while let self = self {
                do {
                    let notifications = try await self.powerWatchdogStatus()
                    for try await notification in notifications {
                        update(notification)
                    }
                }
                catch {
                    print("[\(peripheral)]: \(error)")
                    try? await Task.sleep(timeInterval: 5.0)
                }
            }
        }
    }
    
    func update(_ status: PowerWatchdog.Status) {
        let peripheral = self.peripheral
        print("[\(peripheral)]: \(status.line) \(status.voltage)V \(status.amperage)A \(status.watts)W \(status.totalWatts)kWh")
        switch status.line {
        case 0:
            self.contactSensor.contactSensorState.value = status.voltage > 100 ? .detected : .notdetected
            self.surgeProtector.voltage.value = status.voltage
            self.surgeProtector.current.value = status.amperage
            self.surgeProtector.consumption.value = status.watts
            self.surgeProtector.totalConsumption.value = status.totalWatts
            self.surgeProtector.frequency.value = status.frequency
        case 1:
            break
        default:
            break
        }
    }
}

// MARK: - Battery Service

extension PowerWatchdogAccessory {
    
    final class SurgeProtectorService: HAP.Service {
        
        let voltage = GenericCharacteristic<Float>(
            type: .eveVoltage,
            value: 120,
            permissions: [.read, .events],
            description: "Voltage",
            format: .float,
            unit: .none
        )
        
        let current = GenericCharacteristic<Float>(
            type: .eveCurrent,
            value: 0,
            permissions: [.read, .events],
            description: "Current",
            format: .float,
            unit: .none
        )
        
        let consumption = GenericCharacteristic<Float>(
            type: .eveConsumption,
            value: 0,
            permissions: [.read, .events],
            description: "Consumption",
            format: .float,
            unit: .none
        )
        
        let totalConsumption = GenericCharacteristic<Float>(
            type: .eveTotalConsumption,
            value: 0,
            permissions: [.read, .events],
            description: "Total Consumption",
            format: .float,
            unit: .none
        )
        
        let frequency = GenericCharacteristic<Float>(
            type: .custom(UUID(uuidString: "D1957F69-BAFB-4508-A4D1-573C606B0067")!),
            value: 60,
            permissions: [.read, .events],
            description: "Frequency",
            format: .float,
            unit: .none
        )
        
        let line = GenericCharacteristic<UInt8>(
            type: .custom(UUID(uuidString: "6F2B1F3E-95A6-496B-99A4-C853BE14DA01")!),
            value: 1,
            permissions: [.read],
            description: "Line",
            format: .uint8,
            unit: .none
        )
        
        private let lineValue: PowerWatchdog.Line
        
        init(line lineValue: PowerWatchdog.Line) {
            let name = PredefinedCharacteristic.name("Surge Protector")
            self.lineValue = lineValue
            super.init(type: ServiceType.custom(UUID(uuidString: "6F2B1F3E-95A6-496B-99A4-C853BE14DA00")!), characteristics: [
                AnyCharacteristic(name),
                AnyCharacteristic(voltage),
                AnyCharacteristic(current),
                AnyCharacteristic(consumption),
                AnyCharacteristic(totalConsumption),
                AnyCharacteristic(frequency),
                AnyCharacteristic(line)
            ])
            self.line.value = lineValue.rawValue + 1
        }
    }
}

// MARK: - BatteryMonitorAdvertisement

extension PowerWatchdog: BatteryMonitorAdvertisement {
    
    static public var accessoryType: BatteryMonitorAccessoryType { .powerWatchdog }
    
    init?(scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) {
        guard let name = scanData.localName,
              let serviceUUIDs = scanData.serviceUUIDs,
              let manufacturerData = scanData.manufacturerData else {
            return nil
        }
        self.init(
            name: name,
            serviceUUIDs: serviceUUIDs,
            manufacturerData: manufacturerData
        )
    }
}

// MARK: - GATT

extension PowerWatchdogAccessory {
    
    /// Recieve Power Watchdog values.
    func powerWatchdogStatus() async throws -> AsyncIndefiniteStream<PowerWatchdog.Status> {
        let connection = try await connect()
        return try await connection.powerWatchdogStatus()
    }
}

internal extension GATTConnection {
    
    func powerWatchdogStatus() async throws -> AsyncIndefiniteStream<PowerWatchdog.Status> {
        guard let characteristic = cache.characteristic(.powerWatchdogTXCharacteristic, service: .powerWatchdogService) else {
            throw BatteryMonitorHomeKitToolError.characteristicNotFound(.powerWatchdogTXCharacteristic)
        }
        return try await central.powerWatchdogStatus(characteristic: characteristic)
    }
}
