// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ResourceManagement is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RESOURCE_MANAGER_ROLE = keccak256("RESOURCE_MANAGER_ROLE");

    struct Resource {
        uint256 id;
        string name;
        uint256 totalSupply;
        uint256 availableSupply;
        uint256 pricePerUnit;
        address tokenAddress;
        bool isActive;
    }

    struct AllocationRequest {
        uint256 resourceId;
        address requester;
        uint256 amount;
        uint256 timestamp;
        bool fulfilled;
    }

    uint256 public resourceCount;
    uint256 public allocationRequestCount;
    mapping(uint256 => Resource) public resources;
    mapping(uint256 => AllocationRequest) public allocationRequests;
    mapping(address => mapping(uint256 => uint256)) public allocatedResources; // user => resourceId => amount

    event ResourceAdded(uint256 indexed resourceId, string name, uint256 totalSupply, uint256 pricePerUnit, address tokenAddress);
    event ResourceUpdated(uint256 indexed resourceId, string name, uint256 totalSupply, uint256 pricePerUnit, address tokenAddress);
    event ResourceDeactivated(uint256 indexed resourceId);
    event ResourceAllocated(uint256 indexed requestId, uint256 indexed resourceId, address indexed requester, uint256 amount);
    event AllocationRequestCreated(uint256 indexed requestId, uint256 indexed resourceId, address indexed requester, uint256 amount);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "ResourceManagement: Caller is not an admin");
        _;
    }

    modifier onlyResourceManager() {
        require(hasRole(RESOURCE_MANAGER_ROLE, msg.sender), "ResourceManagement: Caller is not a resource manager");
        _;
    }

    modifier resourceExists(uint256 resourceId) {
        require(resourceId > 0 && resourceId <= resourceCount, "ResourceManagement: Resource does not exist");
        _;
    }

    constructor(address admin) {
        _setupRole(ADMIN_ROLE, admin);
        _setRoleAdmin(RESOURCE_MANAGER_ROLE, ADMIN_ROLE);
        resourceCount = 0;
        allocationRequestCount = 0;
    }

    function addResource(string memory name, uint256 totalSupply, uint256 pricePerUnit, address tokenAddress) external onlyAdmin {
        require(totalSupply > 0, "ResourceManagement: Total supply must be greater than zero");
        require(pricePerUnit > 0, "ResourceManagement: Price per unit must be greater than zero");

        resourceCount = resourceCount.add(1);
        resources[resourceCount] = Resource({
            id: resourceCount,
            name: name,
            totalSupply: totalSupply,
            availableSupply: totalSupply,
            pricePerUnit: pricePerUnit,
            tokenAddress: tokenAddress,
            isActive: true
        });

        emit ResourceAdded(resourceCount, name, totalSupply, pricePerUnit, tokenAddress);
    }

    function updateResource(uint256 resourceId, string memory name, uint256 totalSupply, uint256 pricePerUnit, address tokenAddress) 
        external 
        onlyResourceManager 
        resourceExists(resourceId) 
    {
        Resource storage resource = resources[resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");

        resource.name = name;
        resource.totalSupply = totalSupply;
        resource.availableSupply = totalSupply.sub(resource.totalSupply.sub(resource.availableSupply)); // Adjust available supply
        resource.pricePerUnit = pricePerUnit;
        resource.tokenAddress = tokenAddress;

        emit ResourceUpdated(resourceId, name, totalSupply, pricePerUnit, tokenAddress);
    }

    function deactivateResource(uint256 resourceId) external onlyAdmin resourceExists(resourceId) {
        resources[resourceId].isActive = false;
        emit ResourceDeactivated(resourceId);
    }

    function requestResourceAllocation(uint256 resourceId, uint256 amount) external nonReentrant resourceExists(resourceId) {
        Resource storage resource = resources[resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");
        require(resource.availableSupply >= amount, "ResourceManagement: Not enough available supply");

        allocationRequestCount = allocationRequestCount.add(1);
        allocationRequests[allocationRequestCount] = AllocationRequest({
            resourceId: resourceId,
            requester: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            fulfilled: false
        });

        emit AllocationRequestCreated(allocationRequestCount, resourceId, msg.sender, amount);
    }

    function fulfillAllocationRequest(uint256 requestId) external onlyResourceManager nonReentrant {
        AllocationRequest storage request = allocationRequests[requestId];
        require(!request.fulfilled, "ResourceManagement: Request already fulfilled");
        Resource storage resource = resources[request.resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");
        require(resource.availableSupply >= request.amount, "ResourceManagement: Not enough available supply");

        resource.availableSupply = resource.availableSupply.sub(request.amount);
        allocatedResources[request.requester][request.resourceId] = allocatedResources[request.requester][request.resourceId].add(request.amount);
        request.fulfilled = true;

        IERC20 token = IERC20(resource.tokenAddress);
        uint256 totalCost = request.amount.mul(resource.pricePerUnit);
        require(token.transferFrom(request.requester, address(this), totalCost), "ResourceManagement: Payment failed");

        emit ResourceAllocated(requestId, request.resourceId, request.requester, request.amount);
    }

    function getResourceDetails(uint256 resourceId) external view resourceExists(resourceId) returns (string memory, uint256, uint256, uint256, address, bool) {
        Resource storage resource = resources[resourceId];
        return (
            resource.name,
            resource.totalSupply,
            resource.availableSupply,
            resource.pricePerUnit,
            resource.tokenAddress,
            resource.isActive
        );
    }

    function getAllocationRequestDetails(uint256 requestId) external view returns (uint256, address, uint256, uint256, bool) {
        AllocationRequest storage request = allocationRequests[requestId];
        return (
            request.resourceId,
            request.requester,
            request.amount,
            request.timestamp,
            request.fulfilled
        );
    }

    function revokeAllocation(uint256 resourceId, uint256 amount) external nonReentrant resourceExists(resourceId) {
        require(allocatedResources[msg.sender][resourceId] >= amount, "ResourceManagement: Not enough allocated resources");

        allocatedResources[msg.sender][resourceId] = allocatedResources[msg.sender][resourceId].sub(amount);
        Resource storage resource = resources[resourceId];
        resource.availableSupply = resource.availableSupply.add(amount);

        IERC20 token = IERC20(resource.tokenAddress);
        uint256 refundAmount = amount.mul(resource.pricePerUnit);
        require(token.transfer(msg.sender, refundAmount), "ResourceManagement: Refund failed");
    }

    function withdrawFunds(address tokenAddress, uint256 amount) external onlyAdmin {
        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(msg.sender, amount), "ResourceManagement: Withdraw failed");
    }

    function allocateBonus(uint256 resourceId, address to, uint256 amount) external onlyAdmin resourceExists(resourceId) {
        Resource storage resource = resources[resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");
        require(resource.availableSupply >= amount, "ResourceManagement: Not enough available supply");

        resource.availableSupply = resource.availableSupply.sub(amount);
        allocatedResources[to][resourceId] = allocatedResources[to][resourceId].add(amount);
    }

    function getAllocatedResources(address user, uint256 resourceId) external view resourceExists(resourceId) returns (uint256) {
        return allocatedResources[user][resourceId];
    }
}
