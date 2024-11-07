// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract IoTDeviceManager is Ownable, AccessControl, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Define role identifiers
    bytes32 public constant DEVICE_MANAGER_ROLE = keccak256("DEVICE_MANAGER_ROLE");
    bytes32 public constant DATA_CONSUMER_ROLE = keccak256("DATA_CONSUMER_ROLE");

    struct Device {
        string deviceId;
        address owner;
        bool active;
        string metadataURI;
        uint256 lastDataTimestamp;
    }

    struct DataPoint {
        uint256 timestamp;
        string dataHash;
    }

    mapping(address => Device) private devices;
    mapping(address => DataPoint[]) private deviceData;
    EnumerableSet.AddressSet private registeredDevices;

    event DeviceRegistered(address indexed deviceAddress, string deviceId, string metadataURI);
    event DeviceDeactivated(address indexed deviceAddress, string deviceId);
    event DeviceReactivated(address indexed deviceAddress, string deviceId);
    event DataSubmitted(address indexed deviceAddress, string dataHash, uint256 timestamp);
    event DeviceOwnershipTransferred(address indexed deviceAddress, address indexed newOwner);

    modifier onlyActiveDevice(address _deviceAddress) {
        require(devices[_deviceAddress].active, "Device is not active");
        _;
    }

    modifier onlyDeviceOwnerOrManager(address _deviceAddress) {
        require(
            hasRole(DEVICE_MANAGER_ROLE, msg.sender) || devices[_deviceAddress].owner == msg.sender,
            "Caller is not device owner or manager"
        );
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {
        // Grant roles to the initial owner
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(DEVICE_MANAGER_ROLE, initialOwner);
        _grantRole(DATA_CONSUMER_ROLE, initialOwner);
    }

    // Function to register a new device
    function registerDevice(
        address _deviceAddress,
        string memory _deviceId,
        string memory _metadataURI
    ) external onlyRole(DEVICE_MANAGER_ROLE) {
        require(!registeredDevices.contains(_deviceAddress), "Device already registered");
        require(bytes(_deviceId).length > 0, "Device ID cannot be empty");
        require(bytes(_metadataURI).length > 0, "Metadata URI cannot be empty");
        
        devices[_deviceAddress] = Device({
            deviceId: _deviceId,
            owner: _deviceAddress,
            active: true,
            metadataURI: _metadataURI,
            lastDataTimestamp: block.timestamp
        });

        registeredDevices.add(_deviceAddress);
        emit DeviceRegistered(_deviceAddress, _deviceId, _metadataURI);
    }

    // Function to deactivate a device
    function deactivateDevice(address _deviceAddress) external {
        require(registeredDevices.contains(_deviceAddress), "Device not registered");
        require(
            hasRole(DEVICE_MANAGER_ROLE, msg.sender) || devices[_deviceAddress].owner == msg.sender,
            "Caller is not device owner or manager"
        );

        devices[_deviceAddress].active = false;
        registeredDevices.remove(_deviceAddress);

        emit DeviceDeactivated(_deviceAddress, devices[_deviceAddress].deviceId);
    }

    // Function to reactivate a device
    function reactivateDevice(address _deviceAddress) external {
        require(!registeredDevices.contains(_deviceAddress), "Device is already active");
        require(
            hasRole(DEVICE_MANAGER_ROLE, msg.sender) || devices[_deviceAddress].owner == msg.sender,
            "Caller is not device owner or manager"
        );

        devices[_deviceAddress].active = true;
        devices[_deviceAddress].lastDataTimestamp = block.timestamp;
        registeredDevices.add(_deviceAddress);

        emit DeviceReactivated(_deviceAddress, devices[_deviceAddress].deviceId);
    }

    // Function for devices to submit data
    function submitData(string memory _dataHash) external onlyActiveDevice(msg.sender) {
        require(bytes(_dataHash).length > 0, "Data hash cannot be empty");

        DataPoint memory newDataPoint = DataPoint({
            timestamp: block.timestamp,
            dataHash: _dataHash
        });

        deviceData[msg.sender].push(newDataPoint);
        devices[msg.sender].lastDataTimestamp = block.timestamp;

        emit DataSubmitted(msg.sender, _dataHash, block.timestamp);
    }

    // Function for data consumers to get device data
    function getDeviceData(address _deviceAddress, uint256 _index)
        external
        view
        onlyRole(DATA_CONSUMER_ROLE)
        returns (uint256, string memory)
    {
        require(registeredDevices.contains(_deviceAddress), "Device not registered");
        require(_index < deviceData[_deviceAddress].length, "Invalid data index");

        DataPoint memory dataPoint = deviceData[_deviceAddress][_index];
        return (dataPoint.timestamp, dataPoint.dataHash);
    }

    // Function to get the number of data points for a device
    function getDeviceDataLength(address _deviceAddress)
        external
        view
        onlyRole(DATA_CONSUMER_ROLE)
        returns (uint256)
    {
        require(registeredDevices.contains(_deviceAddress), "Device not registered");
        return deviceData[_deviceAddress].length;
    }

    // Function to get device details
    function getDeviceDetails(address _deviceAddress)
        external
        view
        returns (string memory, address, bool, string memory, uint256)
    {
        require(devices[_deviceAddress].owner != address(0), "Device not registered");

        Device memory device = devices[_deviceAddress];
        return (
            device.deviceId,
            device.owner,
            device.active,
            device.metadataURI,
            device.lastDataTimestamp
        );
    }

    // Function to update device metadata
    function updateDeviceMetadata(address _deviceAddress, string memory _metadataURI)
        external
        onlyActiveDevice(_deviceAddress)
        onlyDeviceOwnerOrManager(_deviceAddress)
    {
        require(bytes(_metadataURI).length > 0, "Metadata URI cannot be empty");

        devices[_deviceAddress].metadataURI = _metadataURI;
    }

    // Function to transfer device ownership
    function transferDeviceOwnership(address _deviceAddress, address _newOwner)
        external
        onlyActiveDevice(_deviceAddress)
        onlyDeviceOwnerOrManager(_deviceAddress)
    {
        require(_newOwner != address(0), "New owner cannot be zero address");

        devices[_deviceAddress].owner = _newOwner;
        emit DeviceOwnershipTransferred(_deviceAddress, _newOwner);
    }

    // Function to get all registered devices
    function getRegisteredDevices() external view returns (address[] memory) {
        return registeredDevices.values();
    }

    // Function to get the total number of registered devices
    function totalRegisteredDevices() external view returns (uint256) {
        return registeredDevices.length();
    }

    // Function to check if a device is active
    function isDeviceActive(address _deviceAddress) external view returns (bool) {
        return devices[_deviceAddress].active;
    }

    // Function to get the last data submission timestamp for a device
    function getLastDataTimestamp(address _deviceAddress) external view returns (uint256) {
        require(devices[_deviceAddress].owner != address(0), "Device not registered");
        return devices[_deviceAddress].lastDataTimestamp;
    }

    // Function to withdraw tokens (onlyOwner)
    function withdrawTokens(address _token, address _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_token != address(0), "Token address cannot be zero");
        require(_to != address(0), "Recipient address cannot be zero");
        require(_amount > 0, "Amount must be greater than zero");
        IERC20(_token).transfer(_to, _amount);
    }

    // Function to grant DEVICE_MANAGER_ROLE to an account
    function grantManagerRole(address _account) external onlyOwner {
        grantRole(DEVICE_MANAGER_ROLE, _account);
    }

    // Function to revoke DEVICE_MANAGER_ROLE from an account
    function revokeManagerRole(address _account) external onlyOwner {
        revokeRole(DEVICE_MANAGER_ROLE, _account);
    }

    // Function to grant DATA_CONSUMER_ROLE to an account
    function grantDataConsumerRole(address _account) external onlyOwner {
        grantRole(DATA_CONSUMER_ROLE, _account);
    }

    // Function to revoke DATA_CONSUMER_ROLE from an account
    function revokeDataConsumerRole(address _account) external onlyOwner {
        revokeRole(DATA_CONSUMER_ROLE, _account);
    }
}