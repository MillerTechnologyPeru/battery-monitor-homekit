// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "BatteryMonitorHomeKit",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(
            name: "battery-monitor-homekit",
            targets: ["BatteryMonitorHomeKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/MillerTechnologyPeru/HAP.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/PureSwift/Bluetooth.git",
            from: "6.0.0"
        ),
        .package(
            url: "https://github.com/PureSwift/GATT.git",
            from: "3.0.0"
        ),
        .package(
            url: "https://github.com/PureSwift/BluetoothLinux.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/MillerTechnologyPeru/Topdon.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/MillerTechnologyPeru/Leagend.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/MillerTechnologyPeru/HughesAutoformers.git",
            branch: "master"
        )
    ],
    targets: [
        .executableTarget(
            name: "BatteryMonitorHomeKit",
            dependencies: [
                "Topdon",
                "Leagend",
                "HughesAutoformers",
                .product(
                    name: "HAP",
                    package: "HAP"
                ),
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
                .product(
                    name: "Bluetooth",
                    package: "Bluetooth"
                ),
                .product(
                    name: "BluetoothGATT",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothHCI",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothGAP",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "DarwinGATT",
                    package: "GATT",
                    condition: .when(platforms: [.macOS])
                ),
            ]
        ),
        .testTarget(
            name: "BatteryMonitorHomeKitTests",
            dependencies: ["BatteryMonitorHomeKit"]
        )
    ]
)
