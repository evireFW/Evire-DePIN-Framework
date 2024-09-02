// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library IoTIntegration {

    struct IoTDevice {
        uint256 id;
        string deviceType;
        address owner;
        bool active;
        uint256 lastDataTimestamp;
        bytes32[] dataHashes;
        mapping(bytes32 => bytes) dataStorage;
    }

    struct IoTNetwork {
        mapping(uint256 => IoTDevice) devices;
        uint256[] deviceIds;
        mapping(bytes32 => bool) authorizedDataSenders;
    }

    event DeviceRegistered(uint256 indexed deviceId, address indexed owner, string deviceType);
    event DeviceActivated(uint256 indexed deviceId, address indexed owner);
    event DeviceDeactivated(uint256 indexed deviceId, address indexed owner);
    event DataStored(uint256 indexed deviceId, bytes32 dataHash, uint256 timestamp);

    function registerDevice(IoTNetwork storage self, uint256 deviceId, string memory deviceType, address owner) public {
        require(self.devices[deviceId].id == 0, "Device already registered");
        
        IoTDevice storage newDevice = self.devices[deviceId];
        newDevice.id = deviceId;
        newDevice.deviceType = deviceType;
        newDevice.owner = owner;
        newDevice.active = false;

        self.deviceIds.push(deviceId);

        emit DeviceRegistered(deviceId, owner, deviceType);
    }

    function activateDevice(IoTNetwork storage self, uint256 deviceId) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.owner == msg.sender, "Only the owner can activate the device");
        require(!device.active, "Device is already active");

        device.active = true;
        emit DeviceActivated(deviceId, msg.sender);
    }

    function deactivateDevice(IoTNetwork storage self, uint256 deviceId) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.owner == msg.sender, "Only the owner can deactivate the device");
        require(device.active, "Device is already inactive");

        device.active = false;
        emit DeviceDeactivated(deviceId, msg.sender);
    }

    function storeData(IoTNetwork storage self, uint256 deviceId, bytes32 dataHash, bytes memory data) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.active, "Device is not active");
        require(isAuthorizedSender(self, msg.sender), "Unauthorized data sender");

        device.dataHashes.push(dataHash);
        device.dataStorage[dataHash] = data;
        device.lastDataTimestamp = block.timestamp;

        emit DataStored(deviceId, dataHash, block.timestamp);
    }

    function retrieveData(IoTNetwork storage self, uint256 deviceId, bytes32 dataHash) public view returns (bytes memory) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.dataStorage[dataHash].length > 0, "Data not found");

        return device.dataStorage[dataHash];
    }

    function authorizeDataSender(IoTNetwork storage self, bytes32 senderHash) public {
        self.authorizedDataSenders[senderHash] = true;
    }

    function revokeDataSender(IoTNetwork storage self, bytes32 senderHash) public {
        self.authorizedDataSenders[senderHash] = false;
    }

    function isAuthorizedSender(IoTNetwork storage self, address sender) public view returns (bool) {
        return self.authorizedDataSenders[keccak256(abi.encodePacked(sender))];
    }

    function getDeviceDataHashes(IoTNetwork storage self, uint256 deviceId) public view returns (bytes32[] memory) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");

        return device.dataHashes;
    }

    function getActiveDevices(IoTNetwork storage self) public view returns (uint256[] memory) {
        uint256[] memory activeDeviceIds = new uint256[](self.deviceIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < self.deviceIds.length; i++) {
            if (self.devices[self.deviceIds[i]].active) {
                activeDeviceIds[count] = self.deviceIds[i];
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeDeviceIds[i];
        }

        return result;
    }

    function deactivateAllDevices(IoTNetwork storage self) public {
        for (uint256 i = 0; i < self.deviceIds.length; i++) {
            uint256 deviceId = self.deviceIds[i];
            if (self.devices[deviceId].active) {
                self.devices[deviceId].active = false;
                emit DeviceDeactivated(deviceId, self.devices[deviceId].owner);
            }
        }
    }

    function getDeviceOwner(IoTNetwork storage self, uint256 deviceId) public view returns (address) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");

        return device.owner;
    }

    function transferDeviceOwnership(IoTNetwork storage self, uint256 deviceId, address newOwner) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.owner == msg.sender, "Only the owner can transfer ownership");

        device.owner = newOwner;
    }
}
