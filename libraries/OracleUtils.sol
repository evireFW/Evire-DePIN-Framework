// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library OracleUtils {
    struct Oracle {
        address oracleAddress;
        uint256 lastUpdated;
        bytes data;
        bool isActive;
    }

    struct OracleSet {
        mapping(address => Oracle) oracles;
        address[] oracleAddresses;
        uint256 quorum; // Minimum number of oracles needed for a valid result
    }

    event OracleRegistered(address indexed oracleAddress);
    event OracleUpdated(address indexed oracleAddress, bytes data, uint256 timestamp);
    event OracleDeactivated(address indexed oracleAddress);
    event QuorumChanged(uint256 oldQuorum, uint256 newQuorum);

    modifier onlyExistingOracle(OracleSet storage self, address oracleAddress) {
        require(self.oracles[oracleAddress].oracleAddress != address(0), "Oracle does not exist");
        _;
    }

    function registerOracle(OracleSet storage self, address oracleAddress) internal {
        require(self.oracles[oracleAddress].oracleAddress == address(0), "Oracle already registered");
        self.oracles[oracleAddress] = Oracle({
            oracleAddress: oracleAddress,
            lastUpdated: 0,
            data: "",
            isActive: true
        });
        self.oracleAddresses.push(oracleAddress);
        emit OracleRegistered(oracleAddress);
    }

    function deactivateOracle(OracleSet storage self, address oracleAddress) internal onlyExistingOracle(self, oracleAddress) {
        self.oracles[oracleAddress].isActive = false;
        emit OracleDeactivated(oracleAddress);
    }

    function removeOracle(OracleSet storage self, address oracleAddress) internal onlyExistingOracle(self, oracleAddress) {
        delete self.oracles[oracleAddress];
        for (uint256 i = 0; i < self.oracleAddresses.length; i++) {
            if (self.oracleAddresses[i] == oracleAddress) {
                self.oracleAddresses[i] = self.oracleAddresses[self.oracleAddresses.length - 1];
                self.oracleAddresses.pop();
                break;
            }
        }
        emit OracleDeactivated(oracleAddress);
    }

    function updateOracleData(OracleSet storage self, address oracleAddress, bytes memory data) internal onlyExistingOracle(self, oracleAddress) {
        self.oracles[oracleAddress].data = data;
        self.oracles[oracleAddress].lastUpdated = block.timestamp;
        emit OracleUpdated(oracleAddress, data, block.timestamp);
    }

    function setQuorum(OracleSet storage self, uint256 quorum) internal {
        require(quorum > 0 && quorum <= self.oracleAddresses.length, "Invalid quorum");
        uint256 oldQuorum = self.quorum;
        self.quorum = quorum;
        emit QuorumChanged(oldQuorum, quorum);
    }

    function getValidOracles(OracleSet storage self) internal view returns (Oracle[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < self.oracleAddresses.length; i++) {
            Oracle storage oracle = self.oracles[self.oracleAddresses[i]];
            if (oracle.isActive && oracle.lastUpdated > 0) {
                count++;
            }
        }

        Oracle[] memory activeOracles = new Oracle[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < self.oracleAddresses.length; i++) {
            Oracle storage oracle = self.oracles[self.oracleAddresses[i]];
            if (oracle.isActive && oracle.lastUpdated > 0) {
                activeOracles[index] = oracle;
                index++;
            }
        }
        return activeOracles;
    }

    function getAggregatedData(OracleSet storage self) internal view returns (uint256) {
        Oracle[] memory validOracles = getValidOracles(self);
        require(validOracles.length >= self.quorum, "Not enough valid oracles");

        uint256 sum = 0;
        uint256 validCount = 0;
        for (uint256 i = 0; i < validOracles.length; i++) {
            if (validOracles[i].data.length == 32) {
                uint256 oracleData = abi.decode(validOracles[i].data, (uint256));
                sum += oracleData;
                validCount++;
            }
        }

        require(validCount >= self.quorum, "Not enough valid oracle data");
        return sum / validCount;
    }

    function verifyData(OracleSet storage self, bytes memory data) internal view returns (bool) {
        Oracle[] memory validOracles = getValidOracles(self);
        require(validOracles.length >= self.quorum, "Not enough valid oracles");

        uint256 matchingOracles = 0;
        bytes32 dataHash = keccak256(data);
        for (uint256 i = 0; i < validOracles.length; i++) {
            if (keccak256(validOracles[i].data) == dataHash) {
                matchingOracles++;
            }
        }
        return matchingOracles >= self.quorum;
    }

    function getLastUpdatedTimestamp(OracleSet storage self) internal view returns (uint256) {
        uint256 latestTimestamp = 0;
        Oracle[] memory validOracles = getValidOracles(self);
        for (uint256 i = 0; i < validOracles.length; i++) {
            if (validOracles[i].lastUpdated > latestTimestamp) {
                latestTimestamp = validOracles[i].lastUpdated;
            }
        }
        return latestTimestamp;
    }

    function isOracleActive(OracleSet storage self, address oracleAddress) internal view returns (bool) {
        Oracle storage oracle = self.oracles[oracleAddress];
        return oracle.isActive && oracle.oracleAddress != address(0);
    }

    function getOracleData(OracleSet storage self, address oracleAddress) internal view onlyExistingOracle(self, oracleAddress) returns (bytes memory) {
        return self.oracles[oracleAddress].data;
    }

    function getOracleLastUpdated(OracleSet storage self, address oracleAddress) internal view onlyExistingOracle(self, oracleAddress) returns (uint256) {
        return self.oracles[oracleAddress].lastUpdated;
    }

    function countActiveOracles(OracleSet storage self) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < self.oracleAddresses.length; i++) {
            if (self.oracles[self.oracleAddresses[i]].isActive) {
                count++;
            }
        }
        return count;
    }
}
