//
//  BM2.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT
import HAP
import Leagend

final class BM2Accessory: HAP.Accessory.ContactSensor, BatteryMonitorAccessory {
    
    static var accessoryType: BatteryMonitorAccessoryType { .bm2 }
    
    let peripheral: NativeCentral.Peripheral
    
    let central: NativeCentral
    
    let configuration: BridgeConfiguration.Accessory?
    
    let advertisement: Leagend.BM2.Advertisement
    
    let battery = BatteryService()
    
    init(
        peripheral: NativeCentral.Peripheral,
        central: NativeCentral,
        advertisement: Leagend.BM2.Advertisement,
        configuration: BridgeConfiguration.Accessory?
    ) {
        self.peripheral = peripheral
        self.central = central
        self.advertisement = advertisement
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "BM2 Battery Monitor",
            serialNumber: peripheral.description,
            manufacturer: "Leagend",
            model: configuration?.model ?? advertisement.name.rawValue,
            firmwareRevision: "1.0.0"
        )
        super.init(
            info: info,
            additionalServices: [
                battery
            ]
        )
        start()
        //self.bridgeState.accessoryIdentifier.value = advertisement.address.rawValue
    }
}

private extension BM2Accessory {
    
    func start() {
        let peripheral = self.peripheral
        Task { [weak self] in
            while let self = self {
                do {
                    let notifications = try await self.readBM2Voltage()
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
    
    func update(_ notification: BM2.BatteryCharacteristic) {
        let peripheral = self.peripheral
        print("[\(peripheral)]: \(notification.voltage) \(notification.power)")
        let voltage = notification.voltage.voltage
        self.contactSensor.contactSensorState.value = notification.voltage.voltage > 1.0 ? .detected : .notdetected
        self.battery.batteryVoltage.value = voltage
        self.battery.statusLowBattery.value = voltage < 12.0 ? .batteryLow : .batteryNormal
        self.battery.chargingState?.value = voltage > 13.0 ? .charging : .notCharging
        self.battery.batteryLevel?.value = notification.power.rawValue
    }
}

// MARK: - BatteryMonitorAdvertisement

extension Leagend.BM2.Advertisement: BatteryMonitorAdvertisement {
    
    static public var accessoryType: BatteryMonitorAccessoryType { .bm2 }
    
    init?(scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) {
        self.init(scanData)
    }
}

// MARK: - Battery Service

extension BM2Accessory {
    
    final class BatteryService: HAP.Service.Battery {
        
        let batteryVoltage = GenericCharacteristic<Float>(
            type: .custom(UUID(uuidString: "5C7D8287-D288-4F4D-BB4A-161A83A99752")!),
            value: 12,
            permissions: [.read, .events],
            description: "Battery Voltage",
            format: .float,
            unit: .none
        )
        
        init() {
            let name = PredefinedCharacteristic.name("Battery")
            let batteryLevel = PredefinedCharacteristic.batteryLevel()
            let chargingState = PredefinedCharacteristic.chargingState()
            super.init(characteristics: [
                AnyCharacteristic(name),
                AnyCharacteristic(batteryLevel),
                AnyCharacteristic(chargingState),
                AnyCharacteristic(batteryVoltage)
            ])
            self.statusLowBattery.value = .batteryNormal
            self.chargingState?.value = .notCharging
        }
    }
}

// MARK: - GATT

internal extension BM2Accessory {
    
    func readBM2Identifier() async throws -> BluetoothAddress {
        let connection = try await connect()
        return try await connection.readBM2Identifier()
    }
    
    /// Read Voltage
    func readBM2Voltage() async throws -> AsyncIndefiniteStream<BM2.BatteryCharacteristic> {
        let connection = try await connect()
        return try await connection.leagendBM2VoltageNotifications()
    }
}

internal extension GATTConnection {
    
    func leagendBM2VoltageNotifications() async throws -> AsyncIndefiniteStream<BM2.BatteryCharacteristic> {
        guard let characteristic = cache.characteristic(.leagendBM2BatteryVoltageCharacteristic, service: .leagendBM2Service) else {
            throw BatteryMonitorHomeKitToolError.characteristicNotFound(.leagendBM2BatteryVoltageCharacteristic)
        }
        let notifications = try await central.notify(for: characteristic)
        return AsyncIndefiniteStream<BM2.BatteryCharacteristic> { build in
            for try await notification in notifications {
                guard let characteristic = try? BM2.BatteryCharacteristic.decrypt(notification) else {
                    continue
                }
                build(characteristic)
            }
        }
    }
    
    func readBM2Identifier() async throws -> BluetoothAddress {
        guard let characteristic = cache.characteristic(.systemId, service: .deviceInformation) else {
            throw BatteryMonitorHomeKitToolError.characteristicNotFound(.systemId)
        }
        let data = try await central.readValue(for: characteristic)
        guard data.count == 8 else {
            throw BatteryMonitorHomeKitToolError.invalidCharacteristicValue(.systemId)
        }
        let address = BluetoothAddress(
            bigEndian: BluetoothAddress(
                bytes: (
                    data[0],
                    data[1],
                    data[2],
                    data[5],
                    data[6],
                    data[7]
                )
            )
        )
        return address
    }
}
