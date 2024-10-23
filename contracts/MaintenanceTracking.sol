// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MaintenanceTracking is Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;

    // Enum to represent the status of a maintenance request
    enum RequestStatus { Pending, Approved, InProgress, Completed, Canceled }

    // Struct to represent a maintenance request
    struct MaintenanceRequest {
        uint256 id;
        uint256 assetId;
        string description;
        address requester;
        uint256 timestamp;
        uint256 cost;
        address approvedBy;
        address serviceProvider;
        RequestStatus status;
    }

    // Events
    event MaintenanceRequested(uint256 indexed requestId, uint256 indexed assetId, address indexed requester, string description);
    event MaintenanceApproved(uint256 indexed requestId, address indexed approvedBy, uint256 cost, address serviceProvider);
    event MaintenanceStarted(uint256 indexed requestId, address indexed serviceProvider);
    event MaintenanceCompleted(uint256 indexed requestId, uint256 cost, address indexed approvedBy, address indexed serviceProvider);
    event MaintenanceCanceled(uint256 indexed requestId, address indexed requester);
    event MaintenanceRejected(uint256 indexed requestId, address indexed rejectedBy);
    
    // Counter for request IDs
    uint256 private _requestCounter;
    
    // Maintenance requests by their ID
    mapping(uint256 => MaintenanceRequest) private _requests;

    // Active requests for an asset
    mapping(uint256 => EnumerableSet.UintSet) private _activeRequestsByAsset;

    // Function to request maintenance for an asset
    function requestMaintenance(uint256 assetId, string calldata description) external whenNotPaused returns (uint256) {
        _requestCounter++;
        uint256 requestId = _requestCounter;

        _requests[requestId] = MaintenanceRequest({
            id: requestId,
            assetId: assetId,
            description: description,
            requester: msg.sender,
            timestamp: block.timestamp,
            cost: 0,
            approvedBy: address(0),
            serviceProvider: address(0),
            status: RequestStatus.Pending
        });

        _activeRequestsByAsset[assetId].add(requestId);

        emit MaintenanceRequested(requestId, assetId, msg.sender, description);
        return requestId;
    }

    // Function to approve a maintenance request
    function approveMaintenance(uint256 requestId, uint256 cost, address serviceProvider) external onlyOwner whenNotPaused {
        MaintenanceRequest storage request = _requests[requestId];
        require(request.status == RequestStatus.Pending, "MaintenanceTracking: Request not pending or already approved");

        request.cost = cost;
        request.approvedBy = msg.sender;
        request.serviceProvider = serviceProvider;
        request.status = RequestStatus.Approved;

        emit MaintenanceApproved(requestId, msg.sender, cost, serviceProvider);
    }

    // Function for service provider to start maintenance
    function startMaintenance(uint256 requestId) external whenNotPaused {
        MaintenanceRequest storage request = _requests[requestId];
        require(request.serviceProvider == msg.sender, "MaintenanceTracking: Only assigned service provider can start maintenance");
        require(request.status == RequestStatus.Approved, "MaintenanceTracking: Request not approved or already started");

        request.status = RequestStatus.InProgress;

        emit MaintenanceStarted(requestId, msg.sender);
    }

    // Function for service provider to mark maintenance as completed and receive payment
    function completeMaintenance(uint256 requestId) external whenNotPaused nonReentrant {
        MaintenanceRequest storage request = _requests[requestId];
        require(request.status == RequestStatus.InProgress, "MaintenanceTracking: Maintenance not in progress");
        require(request.serviceProvider == msg.sender, "MaintenanceTracking: Only assigned service provider can complete maintenance");

        request.status = RequestStatus.Completed;
        _activeRequestsByAsset[request.assetId].remove(requestId);

        // Transfer funds to serviceProvider
        if (request.cost > 0) {
            require(address(this).balance >= request.cost, "MaintenanceTracking: Insufficient contract balance");
            payable(request.serviceProvider).transfer(request.cost);
        }

        emit MaintenanceCompleted(requestId, request.cost, request.approvedBy, msg.sender);
    }

    // Function to cancel a maintenance request
    function cancelMaintenance(uint256 requestId) external whenNotPaused {
        MaintenanceRequest storage request = _requests[requestId];
        require(request.requester == msg.sender, "MaintenanceTracking: Only requester can cancel");
        require(request.status == RequestStatus.Pending || request.status == RequestStatus.Approved, "MaintenanceTracking: Cannot cancel a request that is in progress or completed");

        request.status = RequestStatus.Canceled;
        _activeRequestsByAsset[request.assetId].remove(requestId);

        emit MaintenanceCanceled(requestId, msg.sender);
    }

    // Function to reject a maintenance request
    function rejectMaintenance(uint256 requestId) external onlyOwner whenNotPaused {
        MaintenanceRequest storage request = _requests[requestId];
        require(request.status == RequestStatus.Pending, "MaintenanceTracking: Can only reject pending requests");

        request.status = RequestStatus.Canceled;
        _activeRequestsByAsset[request.assetId].remove(requestId);

        emit MaintenanceRejected(requestId, msg.sender);
    }

    // Function to get the details of a maintenance request
    function getMaintenanceRequest(uint256 requestId) external view returns (MaintenanceRequest memory) {
        return _requests[requestId];
    }

    // Function to get all active maintenance requests for an asset
    function getActiveRequestsForAsset(uint256 assetId) external view returns (uint256[] memory) {
        return _activeRequestsByAsset[assetId].values();
    }

    // Function to get the total number of maintenance requests
    function totalRequests() external view returns (uint256) {
        return _requestCounter;
    }

    // Function to pause the contract (onlyOwner)
    function pause() external onlyOwner {
        _pause();
    }

    // Function to unpause the contract (onlyOwner)
    function unpause() external onlyOwner {
        _unpause();
    }

    // Function to withdraw funds (onlyOwner)
    function withdrawFunds(address to, uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "MaintenanceTracking: Insufficient balance");
        payable(to).transfer(amount);
    }

    // Fallback function to receive Ether
    receive() external payable {}
    fallback() external payable {}
}
