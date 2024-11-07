// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Maintenance {
    struct MaintenanceRecord {
        uint256 id;
        string description;
        uint256 scheduledTimestamp;
        uint256 completedTimestamp;
        address performedBy;
        bool isCompleted;
    }

    struct MaintenanceSchedule {
        uint256 assetId;
        uint256 interval; // in seconds
        uint256 lastPerformed;
        uint256 nextScheduled;
        MaintenanceRecord[] records;
        bool exists;
    }

    struct MaintenanceManager {
        mapping(uint256 => MaintenanceSchedule) schedules;
        uint256 nextMaintenanceId;
    }

    event MaintenanceScheduled(
        uint256 indexed assetId,
        uint256 indexed maintenanceId,
        uint256 scheduledTimestamp
    );

    event MaintenanceCompleted(
        uint256 indexed assetId,
        uint256 indexed maintenanceId,
        uint256 completedTimestamp,
        address performedBy
    );

    function createMaintenanceSchedule(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 interval
    ) public {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(!schedule.exists, "Schedule already exists");
        schedule.assetId = assetId;
        schedule.interval = interval;
        schedule.exists = true;
    }

    function scheduleMaintenance(
        MaintenanceManager storage self,
        uint256 assetId,
        string memory description,
        uint256 scheduledTimestamp
    ) public returns (uint256) {
        require(scheduledTimestamp > block.timestamp, "Scheduled time must be in the future");

        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");

        uint256 maintenanceId = self.nextMaintenanceId++;
        MaintenanceRecord memory newRecord = MaintenanceRecord({
            id: maintenanceId,
            description: description,
            scheduledTimestamp: scheduledTimestamp,
            completedTimestamp: 0,
            performedBy: address(0),
            isCompleted: false
        });

        schedule.records.push(newRecord);
        schedule.nextScheduled = scheduledTimestamp;

        emit MaintenanceScheduled(
            assetId,
            maintenanceId,
            scheduledTimestamp
        );

        return maintenanceId;
    }

    function performMaintenance(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 maintenanceId,
        address performedBy
    ) public {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        require(
            maintenanceId < schedule.records.length,
            "Invalid maintenance ID"
        );
        MaintenanceRecord storage record = schedule.records[maintenanceId];
        require(!record.isCompleted, "Maintenance already completed");
        require(block.timestamp >= record.scheduledTimestamp, "Maintenance not yet due");

        record.completedTimestamp = block.timestamp;
        record.performedBy = performedBy;
        record.isCompleted = true;

        schedule.lastPerformed = block.timestamp;
        schedule.nextScheduled = block.timestamp + schedule.interval;

        emit MaintenanceCompleted(
            assetId,
            maintenanceId,
            block.timestamp,
            performedBy
        );
    }

    function getNextScheduledMaintenance(
        MaintenanceManager storage self,
        uint256 assetId
    ) public view returns (uint256 nextScheduled, uint256 interval) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        return (schedule.nextScheduled, schedule.interval);
    }

    function getMaintenanceRecordCount(
        MaintenanceManager storage self,
        uint256 assetId
    ) public view returns (uint256) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        return schedule.records.length;
    }

    function getMaintenanceHistory(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 startIndex,
        uint256 count
    ) public view returns (MaintenanceRecord[] memory) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        uint256 totalRecords = schedule.records.length;
        require(startIndex < totalRecords, "Start index out of bounds");

        uint256 endIndex = startIndex + count;
        if (endIndex > totalRecords) {
            endIndex = totalRecords;
        }
        uint256 resultCount = endIndex - startIndex;
        MaintenanceRecord[] memory result = new MaintenanceRecord[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = schedule.records[startIndex + i];
        }
        return result;
    }

    function getMaintenanceRecord(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 maintenanceId
    ) public view returns (MaintenanceRecord memory) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        require(
            maintenanceId < schedule.records.length,
            "Invalid maintenance ID"
        );
        return schedule.records[maintenanceId];
    }

    function updateMaintenanceInterval(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 newInterval
    ) public {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        require(newInterval > 0, "Interval must be positive");
        schedule.interval = newInterval;
        schedule.nextScheduled = block.timestamp + newInterval;
    }

    function isMaintenanceDue(
        MaintenanceManager storage self,
        uint256 assetId
    ) public view returns (bool) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        return block.timestamp >= schedule.nextScheduled;
    }

    function removeMaintenanceRecord(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 maintenanceId
    ) public {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.exists, "Asset does not exist");
        require(
            maintenanceId < schedule.records.length,
            "Invalid maintenance ID"
        );
        MaintenanceRecord storage record = schedule.records[maintenanceId];
        require(!record.isCompleted, "Cannot remove completed maintenance");

        uint256 lastIndex = schedule.records.length - 1;
        if (maintenanceId != lastIndex) {
            schedule.records[maintenanceId] = schedule.records[lastIndex];
        }
        schedule.records.pop();
    }
}
