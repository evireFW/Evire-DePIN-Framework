// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ResourceAllocation is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    struct Resource {
        uint256 totalAmount;
        uint256 allocatedAmount;
        uint256 allocationRate; // e.g., units per block
        uint256 lastUpdatedBlock;
    }

    mapping(address => Resource) public resources;
    mapping(address => mapping(address => uint256)) public allocations; // user => resource => amount
    mapping(address => bool) public authorizedManagers;

    event ResourceCreated(address indexed resource, uint256 totalAmount, uint256 allocationRate);
    event ResourceUpdated(address indexed resource, uint256 newTotalAmount, uint256 newAllocationRate);
    event ResourceAllocated(address indexed resource, address indexed user, uint256 amount);
    event ResourceDeallocated(address indexed resource, address indexed user, uint256 amount);
    event ResourceWithdrawn(address indexed resource, address indexed user, uint256 amount);
    event ManagerAuthorized(address indexed manager, bool isAuthorized);

    modifier onlyAuthorizedManager() {
        require(authorizedManagers[msg.sender], "Not an authorized manager");
        _;
    }

    modifier resourceExists(address resource) {
        require(resources[resource].totalAmount > 0, "Resource does not exist");
        _;
    }

    function createResource(address resource, uint256 totalAmount, uint256 allocationRate) external onlyOwner {
        require(resources[resource].totalAmount == 0, "Resource already exists");
        resources[resource] = Resource({
            totalAmount: totalAmount,
            allocatedAmount: 0,
            allocationRate: allocationRate,
            lastUpdatedBlock: block.number
        });
        emit ResourceCreated(resource, totalAmount, allocationRate);
    }

    function updateResource(address resource, uint256 newTotalAmount, uint256 newAllocationRate) external onlyOwner resourceExists(resource) {
        Resource storage res = resources[resource];
        res.totalAmount = newTotalAmount;
        res.allocationRate = newAllocationRate;
        emit ResourceUpdated(resource, newTotalAmount, newAllocationRate);
    }

    function allocateResource(address resource, address user, uint256 amount) external onlyAuthorizedManager resourceExists(resource) nonReentrant {
        Resource storage res = resources[resource];
        require(res.totalAmount.sub(res.allocatedAmount) >= amount, "Not enough resources available");
        
        res.allocatedAmount = res.allocatedAmount.add(amount);
        allocations[user][resource] = allocations[user][resource].add(amount);

        emit ResourceAllocated(resource, user, amount);
    }

    function deallocateResource(address resource, address user, uint256 amount) external onlyAuthorizedManager resourceExists(resource) nonReentrant {
        require(allocations[user][resource] >= amount, "Insufficient allocated resources");

        Resource storage res = resources[resource];
        res.allocatedAmount = res.allocatedAmount.sub(amount);
        allocations[user][resource] = allocations[user][resource].sub(amount);

        emit ResourceDeallocated(resource, user, amount);
    }

    function withdrawResource(address resource, uint256 amount) external resourceExists(resource) nonReentrant {
        uint256 allocated = allocations[msg.sender][resource];
        require(allocated >= amount, "Insufficient allocated amount");
        require(IERC20(resource).balanceOf(address(this)) >= amount, "Insufficient resource balance");

        allocations[msg.sender][resource] = allocated.sub(amount);
        resources[resource].allocatedAmount = resources[resource].allocatedAmount.sub(amount);
        
        IERC20(resource).transfer(msg.sender, amount);

        emit ResourceWithdrawn(resource, msg.sender, amount);
    }

    function authorizeManager(address manager, bool isAuthorized) external onlyOwner {
        authorizedManagers[manager] = isAuthorized;
        emit ManagerAuthorized(manager, isAuthorized);
    }

    function getAvailableResources(address resource) external view resourceExists(resource) returns (uint256) {
        Resource storage res = resources[resource];
        return res.totalAmount.sub(res.allocatedAmount);
    }

    function getAllocation(address resource, address user) external view resourceExists(resource) returns (uint256) {
        return allocations[user][resource];
    }

    function updateAllocations(address resource) external resourceExists(resource) {
        Resource storage res = resources[resource];
        uint256 blocksPassed = block.number.sub(res.lastUpdatedBlock);
        uint256 additionalAllocations = blocksPassed.mul(res.allocationRate);

        if (additionalAllocations > 0 && res.totalAmount.sub(res.allocatedAmount) >= additionalAllocations) {
            res.allocatedAmount = res.allocatedAmount.add(additionalAllocations);
            res.lastUpdatedBlock = block.number;
        }
    }

    function emergencyWithdraw(address resource, uint256 amount) external onlyOwner resourceExists(resource) nonReentrant {
        IERC20(resource).transfer(owner(), amount);
    }
}
