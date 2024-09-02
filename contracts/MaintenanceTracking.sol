// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MaintenanceTracking is Ownable, Pausable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    // Struct to represent a maintenance request
    struct MaintenanceRequest {
        uint256 id;
        uint256 assetId;
        string description;
        address requester;
        uint256 timestamp;
        bool completed;
        uint256 cost;
        address approvedBy;
    }

    // Events
    event MaintenanceRequested(uint256 indexed requestId, uint256 indexed assetId, address indexed requester, string description);
    event MaintenanceCompleted(uint256 indexed requestId, uint256 cost, address indexed approvedBy);
    event MaintenanceApproved(uint256 indexed requestId, address indexed approvedBy, uint256 cost);
    event MaintenanceCanceled(uint256 indexed requestId, address indexed requester);
    
    // Counters
    Counters.Counter private _requestCounter;
    
    // Maintenance requests by their ID
    mapping(uint256 => MaintenanceRequest) private _requests;

    // Active requests for an asset
    mapping(uint256 => EnumerableSet.UintSet) private _activeRequestsByAsset;

    // Approved maintenance budget
    mapping(address => uint256) private _approvedBudget;

    // Function to request maintenance for an asset
    function requestMaintenance(uint256 assetId, string calldata description) external whenNotPaused returns (uint256) {
        _requestCounter.increment();
        uint256 requestId = _requestCounter.current();

        _requests[requestId] = MaintenanceRequest({
            id: requestId,
            assetId: assetId,
            description: description,
            requester: msg.sender,
            timestamp: block.timestamp,
            completed: false,
            cost: 0,
            approvedBy: address(0)
        });

        _activeRequestsByAsset[assetId].add(requestId);

        emit MaintenanceRequested(requestId, assetId, msg.sender, description);
        return requestId;
    }

    // Function to approve a maintenance request
    function approveMaintenance(uint256 requestId, uint256 cost) external onlyOwner whenNotPaused {
        MaintenanceRequest storage request = _requests[requestId];
        require(!request.completed, "MaintenanceTracking: Request already completed");
        require(request.approvedBy == address(0), "MaintenanceTracking: Request already approved");

        request.cost = cost;
        request.approvedBy = msg.sender;

        _approvedBudget[request.requester] = _approvedBudget[request.requester].add(cost);

        emit MaintenanceApproved(requestId, msg.sender, cost);
    }

    // Function to mark a maintenance request as completed
    function completeMaintenance(uint256 requestId) external whenNotPaused {
        MaintenanceRequest storage request = _requests[requestId];
        require(request.approvedBy != address(0), "MaintenanceTracking: Request not approved");
        require(!request.completed, "MaintenanceTracking: Request already completed");
        require(msg.sender == request.requester || msg.sender == owner(), "MaintenanceTracking: Only requester or owner can complete");

        request.completed = true;
        _activeRequestsByAsset[request.assetId].remove(requestId);

        emit MaintenanceCompleted(requestId, request.cost, request.approvedBy);
    }

    // Function to cancel a maintenance request
    function cancelMaintenance(uint256 requestId) external whenNotPaused {
        MaintenanceRequest storage request = _requests[requestId];
        require(request.requester == msg.sender, "MaintenanceTracking: Only requester can cancel");
        require(!request.completed, "MaintenanceTracking: Cannot cancel a completed request");

        _activeRequestsByAsset[request.assetId].remove(requestId);
        delete _requests[requestId];

        emit MaintenanceCanceled(requestId, msg.sender);
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
        return _requestCounter.current();
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
    function withdrawFunds(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).transfer(to, amount);
        }
    }
}
