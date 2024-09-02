// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

    function scheduleMaintenance(
        MaintenanceManager storage self,
        uint256 assetId,
        string memory description,
        uint256 interval
    ) public returns (uint256) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        schedule.assetId = assetId;
        schedule.interval = interval;
        schedule.lastPerformed = block.timestamp;
        schedule.nextScheduled = block.timestamp + interval;

        uint256 maintenanceId = self.nextMaintenanceId++;
        MaintenanceRecord memory newRecord = MaintenanceRecord({
            id: maintenanceId,
            description: description,
            scheduledTimestamp: schedule.nextScheduled,
            completedTimestamp: 0,
            performedBy: address(0),
            isCompleted: false
        });

        schedule.records.push(newRecord);

        emit MaintenanceScheduled(
            assetId,
            maintenanceId,
            schedule.nextScheduled
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
        require(schedule.assetId != 0, "Asset does not exist");
        require(
            maintenanceId < schedule.records.length,
            "Invalid maintenance ID"
        );
        MaintenanceRecord storage record = schedule.records[maintenanceId];
        require(!record.isCompleted, "Maintenance already completed");

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
    ) public view returns (uint256, uint256) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        return (schedule.nextScheduled, schedule.interval);
    }

    function getMaintenanceHistory(
        MaintenanceManager storage self,
        uint256 assetId
    ) public view returns (MaintenanceRecord[] memory) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        return schedule.records;
    }

    function getMaintenanceRecord(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 maintenanceId
    ) public view returns (MaintenanceRecord memory) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.assetId != 0, "Asset does not exist");
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
        require(schedule.assetId != 0, "Asset does not exist");
        schedule.interval = newInterval;
        schedule.nextScheduled = block.timestamp + newInterval;
    }

    function isMaintenanceDue(
        MaintenanceManager storage self,
        uint256 assetId
    ) public view returns (bool) {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        return block.timestamp >= schedule.nextScheduled;
    }

    function removeMaintenanceRecord(
        MaintenanceManager storage self,
        uint256 assetId,
        uint256 maintenanceId
    ) public {
        MaintenanceSchedule storage schedule = self.schedules[assetId];
        require(schedule.assetId != 0, "Asset does not exist");
        require(
            maintenanceId < schedule.records.length,
            "Invalid maintenance ID"
        );
        MaintenanceRecord[] storage records = schedule.records;

        for (uint256 i = maintenanceId; i < records.length - 1; i++) {
            records[i] = records[i + 1];
        }
        records.pop();
    }
}
