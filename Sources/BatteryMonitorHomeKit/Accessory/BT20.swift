//
//  BT20.swift
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

final class BT20Accessory: HAP.Accessory.ContactSensor, BatteryMonitorAccessory {
    
    static var accessoryType: BatteryMonitorAccessoryType { .bt20 }
    
    let peripheral: NativeCentral.Peripheral
    
    let central: NativeCentral
    
    let configuration: BridgeConfiguration.Accessory?
    
    let advertisement: Topdon.BT20
    
    let battery = BatteryService()
    
    init(
        peripheral: NativeCentral.Peripheral,
        central: NativeCentral,
        advertisement: Topdon.BT20,
        configuration: BridgeConfiguration.Accessory?
    ) {
        self.peripheral = peripheral
        self.central = central
        self.advertisement = advertisement
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "BT20 Battery Monitor",
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
        start()
        //self.bridgeState.accessoryIdentifier.value = advertisement.address.rawValue
    }
}

private extension BT20Accessory {
    
    func start() {
        let peripheral = self.peripheral
        let address = self.advertisement.address
        Task { [weak self] in
            while let self = self {
                do {
                    let notifications = try await self.readBT20Voltage()
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
    
    func update(_ notification: BT20.BatteryVoltageNotification) {
        let address = advertisement.address
        print("[\(address)]: \(notification.voltage.description)")
        let voltage = notification.voltage.voltage
        self.contactSensor.contactSensorState.value = notification.voltage.voltage > 1.0 ? .detected : .notdetected
        self.battery.batteryVoltage.value = voltage
        self.battery.statusLowBattery.value = voltage < 12.0 ? .batteryLow : .batteryNormal
        self.battery.chargingState?.value = voltage > 13.0 ? .charging : .notCharging
    }
}

// MARK: - BatteryMonitorAdvertisement

extension Topdon.BT20: BatteryMonitorAdvertisement {
    
    static public var accessoryType: BatteryMonitorAccessoryType { .bt20 }
    
    init?(scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) {
        self.init(scanData)
    }
}

// MARK: - Battery Service

extension BT20Accessory {
    
    final class BatteryService: HAP.Service.Battery {
        
        let batteryVoltage = GenericCharacteristic<Float>(
            type: .custom(UUID(uuidString: "5C7D8287-D288-4F4D-BB4A-161A83A99752")!),
            value: 12,
            permissions: [.read, .events],
            description: "Battery Voltage",
            format: .float,
            unit: .none
        )
        
        /*
        let batteryCurrent = GenericCharacteristic<Float>(
            type: .eveCurrent,
            value: 0,
            permissions: [.read, .events],
            description: "Battery Current",
            format: .float,
            unit: .none
        )
        */
        init() {
            let name = PredefinedCharacteristic.name("Battery")
            //let batteryLevel = PredefinedCharacteristic.batteryLevel()
            let chargingState = PredefinedCharacteristic.chargingState()
            super.init(characteristics: [
                AnyCharacteristic(name),
                //AnyCharacteristic(batteryLevel),
                AnyCharacteristic(chargingState),
                AnyCharacteristic(batteryVoltage),
                //AnyCharacteristic(batteryCurrent)
            ])
            self.statusLowBattery.value = .batteryNormal
            self.chargingState?.value = .notCharging
        }
    }
}

// MARK: - GATT

internal extension BT20Accessory {
    
    /// Read BT20 Voltage measurements.
    func readBT20Voltage() async throws -> AsyncIndefiniteStream<Topdon.BT20.BatteryVoltageNotification> {
        let connection = try await connect()
        let notifications = try await connection.recieveBT20Events()
        try await connection.sendBT20Command(BT20.BatteryVoltageCommand())
        return AsyncIndefiniteStream<Topdon.BT20.BatteryVoltageNotification> { build in
            for try await event in notifications {
                switch event.opcode {
                case .bt20BatteryVoltageNotification:
                    let batteryNotification = try event.decode(BT20.BatteryVoltageNotification.self)
                    build(batteryNotification)
                default:
                    continue
                }
            }
        }
    }
}

internal extension GATTConnection {
    
    func sendBT20Command<T>(_ command: T) async throws where T: Equatable, T: Hashable, T: Encodable, T: Sendable, T: TopdonSerialMessage {
        guard let characteristic = cache.characteristic(.telinkSerialPortProtocolCommand, service: .telinkSerialPortProtocolService) else {
            throw BatteryMonitorHomeKitToolError.characteristicNotFound(.telinkSerialPortProtocolCommand)
        }
        try await central.sendSerialPortProtocol(
            command: TopdonCommand(command),
            characteristic: characteristic
        )
    }
    
    func recieveBT20Events() async throws -> AsyncIndefiniteStream<TopdonEvent> {
        guard let characteristic = cache.characteristic(.telinkSerialPortProtocolNotification, service: .telinkSerialPortProtocolService) else {
            throw BatteryMonitorHomeKitToolError.characteristicNotFound(.telinkSerialPortProtocolNotification)
        }
        return try await central.recieveSerialPortProtocol(TopdonEvent.self, characteristic: characteristic)
    }
}
