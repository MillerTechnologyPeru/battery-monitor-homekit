//
//  TB6000Pro.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT
import HAP
import Topdon
import Telink

final class TB6000ProAccessory: HAP.Accessory.Switch, BatteryMonitorAccessory {
    
    static var accessoryType: BatteryMonitorAccessoryType { .tb6000Pro }
    
    let peripheral: NativeCentral.Peripheral
    
    let central: NativeCentral
    
    let configuration: BridgeConfiguration.Accessory?
    
    let advertisement: Topdon.TB6000Pro
    
    let battery = BatteryService()
    
    private var task: Task<Void, Never>?
    
    init(
        peripheral: NativeCentral.Peripheral,
        central: NativeCentral,
        advertisement: Topdon.TB6000Pro,
        configuration: BridgeConfiguration.Accessory?
    ) {
        self.peripheral = peripheral
        self.central = central
        self.advertisement = advertisement
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "Topdon TB6000Pro Battery Charger",
            serialNumber: advertisement.address.rawValue,
            manufacturer: "Topdon",
            model: configuration?.model ?? Swift.type(of: advertisement).name,
            firmwareRevision: "1.0.0"
        )
        super.init(
            info: info,
            additionalServices: [
                battery
            ]
        )
        //self.bridgeState.accessoryIdentifier.value = advertisement.address.rawValue
    }
}

internal extension TB6000ProAccessory {
    
    func setPowerState(_ newValue: Bool) {
        if newValue {
            quickCharge()
        } else {
            task?.cancel()
        }
    }
}

private extension TB6000ProAccessory {
    
    func quickCharge() {
        task?.cancel()
        let peripheral = self.peripheral
        let address = self.advertisement.address
        task = Task { [weak self] in
            while let self = self {
                do {
                    let notifications = try await self.readTB600ProVoltage()
                    for try await notification in notifications {
                        update(notification)
                    }
                }
                catch {
                    print("[\(address)]: \(error)")
                    try? await Task.sleep(timeInterval: 5.0)
                }
            }
        }
    }
    
    func update(_ notification: TB6000Pro.BatteryVoltageNotification) {
        let address = advertisement.address
        print("[\(address)]: \(notification.voltage) \(notification.amperage) \(notification.watts)")
        let voltage = notification.voltage.voltage
        //self.contactSensor.contactSensorState.value = notification.voltage.voltage > 1.0 ? .detected : .notdetected
        self.battery.batteryVoltage.value = voltage
        self.battery.statusLowBattery.value = voltage < 12.0 ? .batteryLow : .batteryNormal
        self.battery.chargingState?.value = voltage > 13.0 ? .charging : .notCharging
        self.battery.batteryCurrent.value = notification.amperage.amperage
        self.battery.batteryWatts.value = notification.watts.watts
    }
}

// MARK: - BatteryMonitorAdvertisement

extension Topdon.TB6000Pro: BatteryMonitorAdvertisement {
    
    static public var accessoryType: BatteryMonitorAccessoryType { .tb6000Pro }
    
    init?(scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) {
        self.init(scanData)
    }
}

// MARK: - HAP Delegate

extension TB6000ProAccessory: HAP.AccessoryDelegate {
    
    
}

// MARK: - Battery Service

extension TB6000ProAccessory {
    
    final class BatteryService: HAP.Service.Battery {
        
        let batteryVoltage = GenericCharacteristic<Float>(
            type: .custom(UUID(uuidString: "5C7D8287-D288-4F4D-BB4A-161A83A99752")!),
            value: 12.0,
            permissions: [.read, .events],
            description: "Battery Voltage",
            format: .float,
            unit: .none
        )
        
        let batteryCurrent = GenericCharacteristic<Float>(
            type: .eveCurrent,
            value: 0,
            permissions: [.read, .events],
            description: "Battery Current",
            format: .float,
            unit: .none
        )
        
        let batteryWatts = GenericCharacteristic<Float>(
            type: .eveConsumption,
            value: 0,
            permissions: [.read, .events],
            description: "Battery Watts",
            format: .float,
            unit: .none
        )
        
        init() {
            let name = PredefinedCharacteristic.name("Battery")
            let chargingState = PredefinedCharacteristic.chargingState()
            super.init(characteristics: [
                AnyCharacteristic(name),
                AnyCharacteristic(chargingState),
                AnyCharacteristic(batteryVoltage),
                AnyCharacteristic(batteryCurrent),
                AnyCharacteristic(batteryWatts)
            ])
            self.statusLowBattery.value = .batteryNormal
            self.chargingState?.value = .notCharging
        }
    }
}

// MARK: - GATT

extension TB6000ProAccessory {
    
    /// Read TB6000Pro Voltage measurements.
    func readTB600ProVoltage() async throws -> AsyncIndefiniteStream<Topdon.TB6000Pro.BatteryVoltageNotification> {
        let connection = try await connect()
        let notifications = try await connection.recieveTB600ProEvents()
        try await connection.sendTB600ProCommand(TB6000Pro.QuickChargeCommand())
        return AsyncIndefiniteStream<TB6000Pro.BatteryVoltageNotification> { build in
            for try await event in notifications {
                switch event.opcode {
                case .tb6000ProBatteryVoltageNotification:
                    let batteryNotification = try event.decode(TB6000Pro.BatteryVoltageNotification.self)
                    build(batteryNotification)
                default:
                    continue
                }
            }
        }
    }
}

internal extension GATTConnection {
    
    func sendTB600ProCommand<T>(_ command: T) async throws where T: Equatable, T: Hashable, T: Encodable, T: Sendable, T: TopdonSerialMessage {
        guard let characteristic = cache.characteristic(.tb6000ProCharacteristic2, service: .tb6000ProService) else {
            throw BatteryMonitorHomeKitToolError.characteristicNotFound(.tb6000ProCharacteristic2)
        }
        let message = try SerialPortProtocolMessage(command: TopdonCommand(command))
        let data = try message.encode()
        try await central.writeValue(data, for: characteristic, withResponse: false)
    }
    
    func recieveTB600ProEvents() async throws -> AsyncIndefiniteStream<TopdonEvent> {
        guard let characteristic = cache.characteristic(.tb6000ProCharacteristic2, service: .tb6000ProService) else {
            throw BatteryMonitorHomeKitToolError.characteristicNotFound(.tb6000ProCharacteristic2)
        }
        let notifications = try await central.notify(for: characteristic)
        return AsyncIndefiniteStream<TopdonEvent> { build in
            for try await data in notifications {
                let message = try SerialPortProtocolMessage(from: data)
                let event = try TopdonEvent.init(from: message)
                build(event)
            }
        }
    }
}
