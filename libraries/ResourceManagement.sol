// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ResourceManagement is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
    mapping(address => mapping(uint256 => uint256)) public allocatedResources;

    event ResourceAdded(
        uint256 indexed resourceId,
        string name,
        uint256 totalSupply,
        uint256 pricePerUnit,
        address tokenAddress
    );
    event ResourceUpdated(
        uint256 indexed resourceId,
        string name,
        uint256 totalSupply,
        uint256 pricePerUnit,
        address tokenAddress
    );
    event ResourceDeactivated(uint256 indexed resourceId);
    event ResourceAllocated(
        uint256 indexed requestId,
        uint256 indexed resourceId,
        address indexed requester,
        uint256 amount
    );
    event AllocationRequestCreated(
        uint256 indexed requestId,
        uint256 indexed resourceId,
        address indexed requester,
        uint256 amount
    );
    event AllocationRevoked(
        uint256 indexed resourceId,
        address indexed requester,
        uint256 amount
    );
    event FundsWithdrawn(address indexed tokenAddress, uint256 amount);
    event BonusAllocated(
        uint256 indexed resourceId,
        address indexed to,
        uint256 amount
    );

    modifier resourceExists(uint256 resourceId) {
        require(
            resourceId > 0 && resourceId <= resourceCount,
            "ResourceManagement: Resource does not exist"
        );
        _;
    }

     constructor(address admin) {
        require(
            admin != address(0),
            "ResourceManagement: Admin address cannot be zero"
        );
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _setRoleAdmin(RESOURCE_MANAGER_ROLE, ADMIN_ROLE);
        resourceCount = 0;
        allocationRequestCount = 0;
    }

    function addResource(
        string memory name,
        uint256 totalSupply,
        uint256 pricePerUnit,
        address tokenAddress
    ) external onlyRole(ADMIN_ROLE) {
        require(
            bytes(name).length > 0,
            "ResourceManagement: Name cannot be empty"
        );
        require(
            totalSupply > 0,
            "ResourceManagement: Total supply must be greater than zero"
        );
        require(
            pricePerUnit > 0,
            "ResourceManagement: Price per unit must be greater than zero"
        );
        require(
            tokenAddress != address(0),
            "ResourceManagement: Token address cannot be zero"
        );

        resourceCount += 1;
        resources[resourceCount] = Resource({
            id: resourceCount,
            name: name,
            totalSupply: totalSupply,
            availableSupply: totalSupply,
            pricePerUnit: pricePerUnit,
            tokenAddress: tokenAddress,
            isActive: true
        });

        emit ResourceAdded(
            resourceCount,
            name,
            totalSupply,
            pricePerUnit,
            tokenAddress
        );
    }

    function updateResource(
        uint256 resourceId,
        string memory name,
        uint256 totalSupply,
        uint256 pricePerUnit,
        address tokenAddress
    ) external onlyRole(RESOURCE_MANAGER_ROLE) resourceExists(resourceId) {
        Resource storage resource = resources[resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");
        require(
            bytes(name).length > 0,
            "ResourceManagement: Name cannot be empty"
        );
        require(
            totalSupply > 0,
            "ResourceManagement: Total supply must be greater than zero"
        );
        require(
            pricePerUnit > 0,
            "ResourceManagement: Price per unit must be greater than zero"
        );
        require(
            tokenAddress != address(0),
            "ResourceManagement: Token address cannot be zero"
        );

        uint256 allocated = resource.totalSupply - resource.availableSupply;
        require(
            totalSupply >= allocated,
            "ResourceManagement: New total supply cannot be less than allocated amount"
        );

        resource.name = name;
        resource.totalSupply = totalSupply;
        resource.availableSupply = totalSupply - allocated;
        resource.pricePerUnit = pricePerUnit;
        resource.tokenAddress = tokenAddress;

        emit ResourceUpdated(
            resourceId,
            name,
            totalSupply,
            pricePerUnit,
            tokenAddress
        );
    }

    function deactivateResource(uint256 resourceId)
        external
        onlyRole(ADMIN_ROLE)
        resourceExists(resourceId)
    {
        resources[resourceId].isActive = false;
        emit ResourceDeactivated(resourceId);
    }

    function requestResourceAllocation(uint256 resourceId, uint256 amount)
        external
        nonReentrant
        resourceExists(resourceId)
    {
        Resource storage resource = resources[resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");
        require(amount > 0, "ResourceManagement: Amount must be greater than zero");
        require(
            resource.availableSupply >= amount,
            "ResourceManagement: Not enough available supply"
        );

        allocationRequestCount += 1;
        allocationRequests[allocationRequestCount] = AllocationRequest({
            resourceId: resourceId,
            requester: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            fulfilled: false
        });

        emit AllocationRequestCreated(
            allocationRequestCount,
            resourceId,
            msg.sender,
            amount
        );
    }

    function fulfillAllocationRequest(uint256 requestId)
        external
        onlyRole(RESOURCE_MANAGER_ROLE)
        nonReentrant
    {
        AllocationRequest storage request = allocationRequests[requestId];
        require(
            !request.fulfilled,
            "ResourceManagement: Request already fulfilled"
        );
        Resource storage resource = resources[request.resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");
        require(
            resource.availableSupply >= request.amount,
            "ResourceManagement: Not enough available supply"
        );

        resource.availableSupply -= request.amount;
        allocatedResources[request.requester][request.resourceId] += request.amount;
        request.fulfilled = true;

        IERC20 token = IERC20(resource.tokenAddress);
        uint256 totalCost = request.amount * resource.pricePerUnit;
        token.safeTransferFrom(request.requester, address(this), totalCost);

        emit ResourceAllocated(
            requestId,
            request.resourceId,
            request.requester,
            request.amount
        );
    }

    function getResourceDetails(uint256 resourceId)
        external
        view
        resourceExists(resourceId)
        returns (
            string memory name,
            uint256 totalSupply,
            uint256 availableSupply,
            uint256 pricePerUnit,
            address tokenAddress,
            bool isActive
        )
    {
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

    function getAllocationRequestDetails(uint256 requestId)
        external
        view
        returns (
            uint256 resourceId,
            address requester,
            uint256 amount,
            uint256 timestamp,
            bool fulfilled
        )
    {
        AllocationRequest storage request = allocationRequests[requestId];
        return (
            request.resourceId,
            request.requester,
            request.amount,
            request.timestamp,
            request.fulfilled
        );
    }

    function revokeAllocation(uint256 resourceId, uint256 amount)
        external
        nonReentrant
        resourceExists(resourceId)
    {
        require(amount > 0, "ResourceManagement: Amount must be greater than zero");
        require(
            allocatedResources[msg.sender][resourceId] >= amount,
            "ResourceManagement: Not enough allocated resources"
        );

        allocatedResources[msg.sender][resourceId] -= amount;
        Resource storage resource = resources[resourceId];
        resource.availableSupply += amount;

        IERC20 token = IERC20(resource.tokenAddress);
        uint256 refundAmount = amount * resource.pricePerUnit;
        token.safeTransfer(msg.sender, refundAmount);

        emit AllocationRevoked(resourceId, msg.sender, amount);
    }

    function withdrawFunds(address tokenAddress, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(
            tokenAddress != address(0),
            "ResourceManagement: Token address cannot be zero"
        );
        IERC20 token = IERC20(tokenAddress);
        token.safeTransfer(msg.sender, amount);

        emit FundsWithdrawn(tokenAddress, amount);
    }

    function allocateBonus(
        uint256 resourceId,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) resourceExists(resourceId) {
        require(to != address(0), "ResourceManagement: Recipient address cannot be zero");
        require(amount > 0, "ResourceManagement: Amount must be greater than zero");

        Resource storage resource = resources[resourceId];
        require(resource.isActive, "ResourceManagement: Resource is not active");
        require(
            resource.availableSupply >= amount,
            "ResourceManagement: Not enough available supply"
        );

        resource.availableSupply -= amount;
        allocatedResources[to][resourceId] += amount;

        emit BonusAllocated(resourceId, to, amount);
    }

    function getAllocatedResources(address user, uint256 resourceId)
        external
        view
        resourceExists(resourceId)
        returns (uint256)
    {
        return allocatedResources[user][resourceId];
    }

    function listResources() external view returns (Resource[] memory) {
        Resource[] memory allResources = new Resource[](resourceCount);
        for (uint256 i = 1; i <= resourceCount; i++) {
            allResources[i - 1] = resources[i];
        }
        return allResources;
    }
}
