// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library IoTIntegration {

    uint256 constant MAX_DATA_SIZE = 1024; // Max data size in bytes
    uint256 constant MAX_DATA_ENTRIES = 1000; // Max number of data entries per device

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
        address owner;
        mapping(uint256 => IoTDevice) devices;
        uint256[] deviceIds;
        mapping(address => bool) authorizedDataSenders;
    }

    event DeviceRegistered(uint256 indexed deviceId, address indexed owner, string deviceType);
    event DeviceActivated(uint256 indexed deviceId, address indexed owner);
    event DeviceDeactivated(uint256 indexed deviceId, address indexed owner);
    event DeviceRemoved(uint256 indexed deviceId, address indexed owner);
    event DeviceOwnershipTransferred(uint256 indexed deviceId, address indexed previousOwner, address indexed newOwner);
    event NetworkOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event DataStored(uint256 indexed deviceId, bytes32 dataHash, uint256 timestamp);
    event DataRemoved(uint256 indexed deviceId, bytes32 dataHash);

    function initializeNetwork(IoTNetwork storage self, address owner) public {
        require(self.owner == address(0), "Network already initialized");
        self.owner = owner;
    }

    function registerDevice(IoTNetwork storage self, uint256 deviceId, string memory deviceType, address owner) public {
        require(self.owner == msg.sender, "Only the network owner can register devices");
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
        require(device.owner == msg.sender || self.owner == msg.sender, "Not authorized to activate device");
        require(!device.active, "Device is already active");

        device.active = true;
        emit DeviceActivated(deviceId, device.owner);
    }

    function deactivateDevice(IoTNetwork storage self, uint256 deviceId) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.owner == msg.sender || self.owner == msg.sender, "Not authorized to deactivate device");
        require(device.active, "Device is already inactive");

        device.active = false;
        emit DeviceDeactivated(deviceId, device.owner);
    }

    function deactivateAllDevices(IoTNetwork storage self) public {
        require(self.owner == msg.sender, "Only the network owner can deactivate all devices");
        for (uint256 i = 0; i < self.deviceIds.length; i++) {
            uint256 deviceId = self.deviceIds[i];
            if (self.devices[deviceId].active) {
                self.devices[deviceId].active = false;
                emit DeviceDeactivated(deviceId, self.devices[deviceId].owner);
            }
        }
    }

    function removeDevice(IoTNetwork storage self, uint256 deviceId) public {
        require(self.owner == msg.sender, "Only the network owner can remove a device");
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");

        for (uint256 i = 0; i < self.deviceIds.length; i++) {
            if (self.deviceIds[i] == deviceId) {
                self.deviceIds[i] = self.deviceIds[self.deviceIds.length - 1];
                self.deviceIds.pop();
                break;
            }
        }

        address deviceOwner = device.owner;
        delete self.devices[deviceId];

        emit DeviceRemoved(deviceId, deviceOwner);
    }

    function transferDeviceOwnership(IoTNetwork storage self, uint256 deviceId, address newOwner) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.owner == msg.sender, "Only the device owner can transfer ownership");

        address previousOwner = device.owner;
        device.owner = newOwner;

        emit DeviceOwnershipTransferred(deviceId, previousOwner, newOwner);
    }

    function transferNetworkOwnership(IoTNetwork storage self, address newOwner) public {
        require(self.owner == msg.sender, "Only the network owner can transfer ownership");
        address previousOwner = self.owner;
        self.owner = newOwner;

        emit NetworkOwnershipTransferred(previousOwner, newOwner);
    }

    function authorizeDataSender(IoTNetwork storage self, address sender) public {
        require(self.owner == msg.sender, "Only the network owner can authorize data senders");
        self.authorizedDataSenders[sender] = true;
    }

    function revokeDataSender(IoTNetwork storage self, address sender) public {
        require(self.owner == msg.sender, "Only the network owner can revoke data senders");
        self.authorizedDataSenders[sender] = false;
    }

    function isAuthorizedSender(IoTNetwork storage self, address sender) public view returns (bool) {
        return self.authorizedDataSenders[sender];
    }

    function storeData(IoTNetwork storage self, uint256 deviceId, bytes32 dataHash, bytes memory data) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.active, "Device is not active");
        require(isAuthorizedSender(self, msg.sender) || device.owner == msg.sender, "Unauthorized data sender");
        require(data.length <= MAX_DATA_SIZE, "Data size exceeds limit");
        require(device.dataHashes.length < MAX_DATA_ENTRIES, "Maximum data entries reached");

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

    function removeData(IoTNetwork storage self, uint256 deviceId, bytes32 dataHash) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.owner == msg.sender || self.owner == msg.sender, "Not authorized to remove data");
        require(device.dataStorage[dataHash].length > 0, "Data not found");

        delete device.dataStorage[dataHash];

        for (uint256 i = 0; i < device.dataHashes.length; i++) {
            if (device.dataHashes[i] == dataHash) {
                device.dataHashes[i] = device.dataHashes[device.dataHashes.length - 1];
                device.dataHashes.pop();
                break;
            }
        }

        emit DataRemoved(deviceId, dataHash);
    }

    function updateDeviceType(IoTNetwork storage self, uint256 deviceId, string memory newDeviceType) public {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(device.owner == msg.sender || self.owner == msg.sender, "Not authorized to update device type");

        device.deviceType = newDeviceType;
    }

    function getDeviceDataHashes(IoTNetwork storage self, uint256 deviceId) public view returns (bytes32[] memory) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");

        return device.dataHashes;
    }

    function getDeviceDataHashesPaginated(IoTNetwork storage self, uint256 deviceId, uint256 startIndex, uint256 endIndex) public view returns (bytes32[] memory) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        require(endIndex >= startIndex, "Invalid indices");
        uint256 maxIndex = device.dataHashes.length;
        if (endIndex > maxIndex) {
            endIndex = maxIndex;
        }

        uint256 length = endIndex - startIndex;
        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            hashes[i] = device.dataHashes[startIndex + i];
        }
        return hashes;
    }

    function getActiveDevices(IoTNetwork storage self) public view returns (uint256[] memory) {
        uint256[] memory activeDeviceIdsTemp = new uint256[](self.deviceIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < self.deviceIds.length; i++) {
            if (self.devices[self.deviceIds[i]].active) {
                activeDeviceIdsTemp[count] = self.deviceIds[i];
                count++;
            }
        }

        uint256[] memory activeDeviceIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            activeDeviceIds[i] = activeDeviceIdsTemp[i];
        }

        return activeDeviceIds;
    }

    function getActiveDevicesPaginated(IoTNetwork storage self, uint256 startIndex, uint256 endIndex) public view returns (uint256[] memory) {
        require(endIndex >= startIndex, "Invalid indices");
        uint256 maxIndex = self.deviceIds.length;
        if (endIndex > maxIndex) {
            endIndex = maxIndex;
        }

        uint256[] memory activeDeviceIdsTemp = new uint256[](endIndex - startIndex);
        uint256 count = 0;

        for (uint256 i = startIndex; i < endIndex; i++) {
            if (self.devices[self.deviceIds[i]].active) {
                activeDeviceIdsTemp[count] = self.deviceIds[i];
                count++;
            }
        }

        uint256[] memory activeDeviceIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            activeDeviceIds[i] = activeDeviceIdsTemp[i];
        }

        return activeDeviceIds;
    }

    function getDeviceOwner(IoTNetwork storage self, uint256 deviceId) public view returns (address) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");

        return device.owner;
    }

    function getDeviceInfo(IoTNetwork storage self, uint256 deviceId) public view returns (uint256, string memory, address, bool, uint256) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        return (device.id, device.deviceType, device.owner, device.active, device.lastDataTimestamp);
    }

    function getTotalDevices(IoTNetwork storage self) public view returns (uint256) {
        return self.deviceIds.length;
    }

    function getDeviceIds(IoTNetwork storage self) public view returns (uint256[] memory) {
        return self.deviceIds;
    }

    function isDeviceActive(IoTNetwork storage self, uint256 deviceId) public view returns (bool) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        return device.active;
    }

    function getDeviceDataCount(IoTNetwork storage self, uint256 deviceId) public view returns (uint256) {
        IoTDevice storage device = self.devices[deviceId];
        require(device.id != 0, "Device not registered");
        return device.dataHashes.length;
    }
}
