// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ResourceAllocation is Ownable(msg.sender), ReentrancyGuard {
    struct Resource {
        uint256 allocatedAmount;
    }

    mapping(address => Resource) private resources;
    mapping(address => mapping(address => uint256)) private allocations; // user => resource => amount
    mapping(address => bool) private authorizedManagers;
    mapping(address => bool) private resourceExistsMapping;
    address[] private resourcesList;

    event ResourceCreated(address indexed resource);
    event ResourceAllocated(address indexed resource, address indexed user, uint256 amount);
    event ResourceDeallocated(address indexed resource, address indexed user, uint256 amount);
    event ResourceWithdrawn(address indexed resource, address indexed user, uint256 amount);
    event ResourceDeposited(address indexed resource, address indexed depositor, uint256 amount);
    event ManagerAuthorized(address indexed manager, bool isAuthorized);
    event UnallocatedWithdrawn(address indexed resource, uint256 amount);

    modifier onlyAuthorizedManager() {
        require(authorizedManagers[msg.sender], "Not an authorized manager");
        _;
    }

    modifier resourceExists(address resource) {
        require(resourceExistsMapping[resource], "Resource does not exist");
        _;
    }

    function createResource(address resource) external onlyOwner {
        require(resource != address(0), "Invalid resource address");
        require(!resourceExistsMapping[resource], "Resource already exists");
        resources[resource] = Resource({
            allocatedAmount: 0
        });
        resourceExistsMapping[resource] = true;
        resourcesList.push(resource);
        emit ResourceCreated(resource);
    }

    function depositResource(address resource, uint256 amount) external nonReentrant {
        require(resourceExistsMapping[resource], "Resource does not exist");
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(resource).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit ResourceDeposited(resource, msg.sender, amount);
    }

    function allocateResource(address resource, address user, uint256 amount) external onlyAuthorizedManager resourceExists(resource) nonReentrant {
        require(user != address(0), "Invalid user address");
        uint256 availableAmount = IERC20(resource).balanceOf(address(this)) - resources[resource].allocatedAmount;
        require(availableAmount >= amount, "Not enough resources available");

        resources[resource].allocatedAmount += amount;
        allocations[user][resource] += amount;

        emit ResourceAllocated(resource, user, amount);
    }

    function deallocateResource(address resource, address user, uint256 amount) external onlyAuthorizedManager resourceExists(resource) nonReentrant {
        require(user != address(0), "Invalid user address");
        require(allocations[user][resource] >= amount, "Insufficient allocated resources");

        resources[resource].allocatedAmount -= amount;
        allocations[user][resource] -= amount;

        emit ResourceDeallocated(resource, user, amount);
    }

    function withdrawResource(address resource, uint256 amount) external resourceExists(resource) nonReentrant {
        require(allocations[msg.sender][resource] >= amount, "Insufficient allocated amount");
        require(IERC20(resource).balanceOf(address(this)) >= amount, "Insufficient resource balance");

        allocations[msg.sender][resource] -= amount;
        resources[resource].allocatedAmount -= amount;
        
        IERC20(resource).transfer(msg.sender, amount);

        emit ResourceWithdrawn(resource, msg.sender, amount);
    }

    function authorizeManager(address manager, bool isAuthorized) external onlyOwner {
        require(manager != address(0), "Invalid manager address");
        authorizedManagers[manager] = isAuthorized;
        emit ManagerAuthorized(manager, isAuthorized);
    }

    function isAuthorizedManager(address manager) external view returns (bool) {
        return authorizedManagers[manager];
    }

    function getAvailableResources(address resource) external view resourceExists(resource) returns (uint256) {
        uint256 totalBalance = IERC20(resource).balanceOf(address(this));
        uint256 availableAmount = totalBalance - resources[resource].allocatedAmount;
        return availableAmount;
    }

    function getAllocation(address resource, address user) external view resourceExists(resource) returns (uint256) {
        return allocations[user][resource];
    }

    function getTotalAllocation(address user) external view returns (uint256) {
        uint256 totalAllocation = 0;
        for (uint i = 0; i < resourcesList.length; i++) {
            address resource = resourcesList[i];
            totalAllocation += allocations[user][resource];
        }
        return totalAllocation;
    }

    function getResources() external view returns (address[] memory) {
        return resourcesList;
    }

    function withdrawUnallocated(address resource, uint256 amount) external onlyOwner resourceExists(resource) nonReentrant {
        uint256 unallocatedAmount = IERC20(resource).balanceOf(address(this)) - resources[resource].allocatedAmount;
        require(unallocatedAmount >= amount, "Insufficient unallocated amount");
        IERC20(resource).transfer(owner(), amount);
        emit UnallocatedWithdrawn(resource, amount);
    }
}
