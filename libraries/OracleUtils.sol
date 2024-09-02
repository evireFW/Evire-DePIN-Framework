// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library OracleUtils {
    struct Oracle {
        address oracleAddress;
        uint256 lastUpdated;
        bytes data;
        bool isActive;
    }

    struct OracleSet {
        Oracle[] oracles;
        mapping(address => uint256) oracleIndex;
        uint256 quorum; // Minimum number of oracles needed for a valid result
    }

    event OracleRegistered(address indexed oracleAddress);
    event OracleUpdated(address indexed oracleAddress, bytes data, uint256 timestamp);
    event OracleDeactivated(address indexed oracleAddress);
    event QuorumChanged(uint256 oldQuorum, uint256 newQuorum);

    modifier onlyExistingOracle(OracleSet storage self, address oracleAddress) {
        require(self.oracleIndex[oracleAddress] > 0, "Oracle does not exist");
        _;
    }

    function registerOracle(OracleSet storage self, address oracleAddress) external {
        require(self.oracleIndex[oracleAddress] == 0, "Oracle already registered");
        self.oracles.push(Oracle({
            oracleAddress: oracleAddress,
            lastUpdated: 0,
            data: "",
            isActive: true
        }));
        self.oracleIndex[oracleAddress] = self.oracles.length;
        emit OracleRegistered(oracleAddress);
    }

    function deactivateOracle(OracleSet storage self, address oracleAddress) external onlyExistingOracle(self, oracleAddress) {
        uint256 index = self.oracleIndex[oracleAddress] - 1;
        self.oracles[index].isActive = false;
        emit OracleDeactivated(oracleAddress);
    }

    function updateOracleData(OracleSet storage self, address oracleAddress, bytes memory data) external onlyExistingOracle(self, oracleAddress) {
        uint256 index = self.oracleIndex[oracleAddress] - 1;
        self.oracles[index].data = data;
        self.oracles[index].lastUpdated = block.timestamp;
        emit OracleUpdated(oracleAddress, data, block.timestamp);
    }

    function setQuorum(OracleSet storage self, uint256 quorum) external {
        require(quorum > 0 && quorum <= self.oracles.length, "Invalid quorum");
        uint256 oldQuorum = self.quorum;
        self.quorum = quorum;
        emit QuorumChanged(oldQuorum, quorum);
    }

    function getValidOracles(OracleSet storage self) internal view returns (Oracle[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < self.oracles.length; i++) {
            if (self.oracles[i].isActive && self.oracles[i].lastUpdated > 0) {
                count++;
            }
        }

        Oracle[] memory activeOracles = new Oracle[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < self.oracles.length; i++) {
            if (self.oracles[i].isActive && self.oracles[i].lastUpdated > 0) {
                activeOracles[index] = self.oracles[i];
                index++;
            }
        }
        return activeOracles;
    }

    function getAggregatedData(OracleSet storage self) internal view returns (bytes memory) {
        Oracle[] memory validOracles = getValidOracles(self);
        require(validOracles.length >= self.quorum, "Not enough valid oracles");

        // Aggregation logic (Simple majority or weighted average -- must decide)
        // Remember: this is highly dependent on the data type and specific use case
        // TODO: better byte data aggregation
        bytes memory aggregatedData = validOracles[0].data;
        for (uint256 i = 1; i < validOracles.length; i++) {
            // Temp: simple concatenation, assuming data is combinable
            aggregatedData = abi.encodePacked(aggregatedData, validOracles[i].data);
        }

        return aggregatedData;
    }

    function verifyData(OracleSet storage self, bytes memory data) internal view returns (bool) {
        Oracle[] memory validOracles = getValidOracles(self);
        require(validOracles.length >= self.quorum, "Not enough valid oracles");

        uint256 matchingOracles = 0;
        for (uint256 i = 0; i < validOracles.length; i++) {
            if (keccak256(validOracles[i].data) == keccak256(data)) {
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
        return self.oracles[self.oracleIndex[oracleAddress] - 1].isActive;
    }

    function getOracleData(OracleSet storage self, address oracleAddress) internal view onlyExistingOracle(self, oracleAddress) returns (bytes memory) {
        return self.oracles[self.oracleIndex[oracleAddress] - 1].data;
    }

    function getOracleLastUpdated(OracleSet storage self, address oracleAddress) internal view onlyExistingOracle(self, oracleAddress) returns (uint256) {
        return self.oracles[self.oracleIndex[oracleAddress] - 1].lastUpdated;
    }

    function countActiveOracles(OracleSet storage self) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < self.oracles.length; i++) {
            if (self.oracles[i].isActive) {
                count++;
            }
        }
        return count;
    }
}
