// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract OracleIntegration is Ownable {
    using SafeMath for uint256;
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

    event OracleAdded(address oracleAddress, address aggregator, uint8 decimals);
    event OracleRemoved(address oracleAddress);
    event UpdateIntervalChanged(uint256 newInterval);
    event ToleranceChanged(uint256 newTolerance);

    constructor(uint256 _updateInterval, uint256 _tolerance) {
        updateInterval = _updateInterval;
        tolerance = _tolerance;
        lastUpdateTime = block.timestamp;
    }

    modifier onlyOracle() {
        require(oracles[msg.sender].isActive, "Caller is not an active oracle");
        _;
    }

    function addOracle(address oracleAddress, address aggregator, uint8 decimals) external onlyOwner {
        require(oracleAddress != address(0), "Invalid oracle address");
        require(aggregator != address(0), "Invalid aggregator address");
        require(!oracleAddresses.contains(oracleAddress), "Oracle already exists");

        oracles[oracleAddress] = OracleData({
            isActive: true,
            aggregator: AggregatorV3Interface(aggregator),
            decimals: decimals
        });

        oracleAddresses.add(oracleAddress);

        emit OracleAdded(oracleAddress, aggregator, decimals);
    }

    function removeOracle(address oracleAddress) external onlyOwner {
        require(oracleAddresses.contains(oracleAddress), "Oracle does not exist");

        oracles[oracleAddress].isActive = false;
        oracleAddresses.remove(oracleAddress);

        emit OracleRemoved(oracleAddress);
    }

    function setUpdateInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Update interval must be greater than zero");
        updateInterval = newInterval;
        emit UpdateIntervalChanged(newInterval);
    }

    function setTolerance(uint256 newTolerance) external onlyOwner {
        require(newTolerance > 0, "Tolerance must be greater than zero");
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
                aggregatedValue = aggregatedValue.add(price.div(int256(10 ** oracle.decimals)));
                activeOracles++;
            }
        }

        require(activeOracles > 0, "No active oracles found");
        return aggregatedValue.div(int256(activeOracles));
    }

    function updateData() external onlyOracle {
        require(block.timestamp >= lastUpdateTime.add(updateInterval), "Update interval not reached");

        int256 latestValue = getLatestData();
        // The following logic assumes an existing `currentValue` state variable
        // that tracks the current value and updates only if within tolerance
		// TODO: logic
        int256 currentValue = latestValue; 

        if (latestValue < currentValue.sub(int256(tolerance)) || latestValue > currentValue.add(int256(tolerance))) {
            // Logic for handling data outside the tolerance range
        } else {
            // Logic for handling data within the tolerance range
            currentValue = latestValue;
        }

        lastUpdateTime = block.timestamp;
        // Additional logic for persisting updated values or triggering events can be added here
    }

    function isOracle(address oracleAddress) public view returns (bool) {
        return oracles[oracleAddress].isActive;
    }

    function oracleCount() public view returns (uint256) {
        return oracleAddresses.length();
    }

    function getOracleDetails(address oracleAddress) public view returns (address aggregator, uint8 decimals, bool isActive) {
        OracleData storage oracle = oracles[oracleAddress];
        return (address(oracle.aggregator), oracle.decimals, oracle.isActive);
    }

    function getAggregatedOracleData() external view returns (int256) {
        return getLatestData();
    }
}
