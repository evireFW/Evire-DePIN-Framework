// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OracleIntegration is Ownable(msg.sender), ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct OracleData {
        bool isActive;
        AggregatorV3Interface aggregator;
        uint8 decimals;
    }

    mapping(address => OracleData) private oracles;
    EnumerableSet.AddressSet private oracleAddresses;
    uint256 public updateInterval;
    uint256 public lastUpdateTime;
    uint256 public tolerance;
    int256 public currentValue;
    uint8 public decimals = 18; // Standard decimals for normalization

    event OracleAdded(address oracleAddress, address aggregator, uint8 decimals);
    event OracleRemoved(address oracleAddress);
    event OracleUpdated(address oracleAddress, address newAggregator, uint8 newDecimals);
    event UpdateIntervalChanged(uint256 newInterval);
    event ToleranceChanged(uint256 newTolerance);
    event DataUpdated(int256 newValue);
    event DataOutOfTolerance(int256 currentValue, int256 newValue);

    constructor(uint256 _updateInterval, uint256 _tolerance) {
        require(_tolerance <= uint256(type(int256).max), "Tolerance too high");
        updateInterval = _updateInterval;
        tolerance = _tolerance;
        lastUpdateTime = block.timestamp;
    }

    modifier onlyOracle() {
        require(oracles[msg.sender].isActive, "Caller is not an active oracle");
        _;
    }

    function addOracle(address oracleAddress, address aggregator, uint8 _decimals) external onlyOwner {
        require(oracleAddress != address(0), "Invalid oracle address");
        require(aggregator != address(0), "Invalid aggregator address");
        require(!oracleAddresses.contains(oracleAddress), "Oracle already exists");
        require(_decimals <= 77, "Decimals too high");

        oracles[oracleAddress] = OracleData({
            isActive: true,
            aggregator: AggregatorV3Interface(aggregator),
            decimals: _decimals
        });

        oracleAddresses.add(oracleAddress);

        emit OracleAdded(oracleAddress, aggregator, _decimals);
    }

    function removeOracle(address oracleAddress) external onlyOwner {
        require(oracleAddresses.contains(oracleAddress), "Oracle does not exist");

        oracles[oracleAddress].isActive = false;
        oracleAddresses.remove(oracleAddress);

        emit OracleRemoved(oracleAddress);
    }

    function updateOracle(address oracleAddress, address newAggregator, uint8 newDecimals) external onlyOwner {
        require(oracleAddresses.contains(oracleAddress), "Oracle does not exist");
        require(newAggregator != address(0), "Invalid aggregator address");
        require(newDecimals <= 77, "Decimals too high");

        OracleData storage oracle = oracles[oracleAddress];
        oracle.aggregator = AggregatorV3Interface(newAggregator);
        oracle.decimals = newDecimals;

        emit OracleUpdated(oracleAddress, newAggregator, newDecimals);
    }

    function setUpdateInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Update interval must be greater than zero");
        updateInterval = newInterval;
        emit UpdateIntervalChanged(newInterval);
    }

    function setTolerance(uint256 newTolerance) external onlyOwner {
        require(newTolerance > 0, "Tolerance must be greater than zero");
        require(newTolerance <= uint256(type(int256).max), "Tolerance too high");
        tolerance = newTolerance;
        emit ToleranceChanged(newTolerance);
    }

    function getLatestData() public view returns (int256) {
        require(oracleAddresses.length() > 0, "No oracles available");

        int256 aggregatedValue = 0;
        uint256 activeOracles = 0;

        for (uint256 i = 0; i < oracleAddresses.length(); i++) {
            OracleData storage oracle = oracles[oracleAddresses.at(i)];
            if (oracle.isActive) {
                (, int256 price, , , ) = oracle.aggregator.latestRoundData();
                int256 adjustedPrice = scalePrice(price, oracle.decimals, decimals);
                aggregatedValue += adjustedPrice;
                activeOracles++;
            }
        }

        require(activeOracles > 0, "No active oracles found");
        int256 averagePrice = aggregatedValue / int256(activeOracles);
        return averagePrice;
    }

    function scalePrice(int256 _price, uint8 _priceDecimals, uint8 _decimals) internal pure returns (int256) {
        if (_priceDecimals < _decimals) {
            return _price * int256(10 ** uint256(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10 ** uint256(_priceDecimals - _decimals));
        } else {
            return _price;
        }
    }

    function updateData() external onlyOracle nonReentrant {
        require(block.timestamp >= lastUpdateTime + updateInterval, "Update interval not reached");

        int256 latestValue = getLatestData();

        if (currentValue == 0) {
            // Initialize currentValue if not set
            currentValue = latestValue;
            emit DataUpdated(currentValue);
        } else if (latestValue < currentValue - int256(tolerance) || latestValue > currentValue + int256(tolerance)) {
            // Data is outside tolerance range
            emit DataOutOfTolerance(currentValue, latestValue);
            // You might decide to reject the update or accept it; here we choose to reject
        } else {
            // Data is within tolerance range
            currentValue = latestValue;
            emit DataUpdated(currentValue);
        }

        lastUpdateTime = block.timestamp;
    }

    function isOracle(address oracleAddress) public view returns (bool) {
        return oracles[oracleAddress].isActive;
    }

    function oracleCount() public view returns (uint256) {
        return oracleAddresses.length();
    }

    function getOracleDetails(address oracleAddress) public view returns (address aggregator, uint8 _decimals, bool isActive) {
        OracleData storage oracle = oracles[oracleAddress];
        return (address(oracle.aggregator), oracle.decimals, oracle.isActive);
    }

    function getAggregatedOracleData() external view returns (int256) {
        return getLatestData();
    }

    function getOracleAddresses() external view returns (address[] memory) {
        return oracleAddresses.values();
    }
}
