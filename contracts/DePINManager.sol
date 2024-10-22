// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract DePINManager is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    error CallerNotAssetOwner();
    error AssetDoesNotExist();
    error InvalidRecipientAddress();
    error AssetAlreadyDeactivated();
    error AssetAlreadyActive();
    error CallerNotOwnerNorApproved();

    struct Asset {
        uint256 id;
        string name;
        string metadataURI;
        uint256 createdAt;
        uint256 updatedAt;
        address owner;
        bool active;
    }

    uint256 private _assetCounter;
    mapping(uint256 => Asset) private _assets;
    mapping(uint256 => address) private _assetApprovals;
    EnumerableSet.AddressSet private _assetOwners;
    mapping(address => EnumerableSet.UintSet) private _ownerAssets;

    event AssetCreated(uint256 indexed assetId, string name, address indexed owner);
    event AssetUpdated(uint256 indexed assetId, string metadataURI, address indexed owner);
    event AssetTransferred(uint256 indexed assetId, address indexed from, address indexed to);
    event AssetDeactivated(uint256 indexed assetId, address indexed owner);
    event AssetReactivated(uint256 indexed assetId, address indexed owner);
    event Approval(address indexed owner, address indexed approved, uint256 indexed assetId);

    modifier onlyAssetOwner(uint256 assetId) {
        if (_assets[assetId].owner != msg.sender) revert CallerNotAssetOwner();
        _;
    }

    modifier assetExists(uint256 assetId) {
        if (_assets[assetId].owner == address(0)) revert AssetDoesNotExist();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {
        _assetCounter = 0;
    }

    function createAsset(string memory name, string memory metadataURI) external returns (uint256) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(metadataURI).length > 0, "MetadataURI cannot be empty");

        _assetCounter += 1;
        uint256 newAssetId = _assetCounter;

        Asset memory newAsset = Asset({
            id: newAssetId,
            name: name,
            metadataURI: metadataURI,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            owner: msg.sender,
            active: true
        });

        _assets[newAssetId] = newAsset;
        _assetOwners.add(msg.sender);
        _ownerAssets[msg.sender].add(newAssetId);

        emit AssetCreated(newAssetId, name, msg.sender);

        return newAssetId;
    }

    function updateAsset(uint256 assetId, string memory metadataURI) external assetExists(assetId) onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        asset.metadataURI = metadataURI;
        asset.updatedAt = block.timestamp;

        emit AssetUpdated(assetId, metadataURI, msg.sender);
    }

    function transferAsset(uint256 assetId, address to) external assetExists(assetId) nonReentrant {
        if (to == address(0)) revert InvalidRecipientAddress();
        address owner = _assets[assetId].owner;
        if (msg.sender != owner && getApproved(assetId) != msg.sender) revert CallerNotOwnerNorApproved();
        _transferAsset(assetId, owner, to);
    }

    function _transferAsset(uint256 assetId, address from, address to) internal {
        _assets[assetId].owner = to;
        _ownerAssets[from].remove(assetId);
        _ownerAssets[to].add(assetId);

        if (_ownerAssets[from].length() == 0) {
            _assetOwners.remove(from);
        }

        _assetOwners.add(to);

        _assetApprovals[assetId] = address(0);

        emit AssetTransferred(assetId, from, to);
    }

    function approve(address to, uint256 assetId) external assetExists(assetId) onlyAssetOwner(assetId) {
        _assetApprovals[assetId] = to;
        emit Approval(msg.sender, to, assetId);
    }

    function getApproved(uint256 assetId) public view assetExists(assetId) returns (address) {
        return _assetApprovals[assetId];
    }

    function deactivateAsset(uint256 assetId) external assetExists(assetId) onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        if (!asset.active) revert AssetAlreadyDeactivated();
        asset.active = false;

        emit AssetDeactivated(assetId, msg.sender);
    }

    function reactivateAsset(uint256 assetId) external assetExists(assetId) onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        if (asset.active) revert AssetAlreadyActive();
        asset.active = true;

        emit AssetReactivated(assetId, msg.sender);
    }

    function getAsset(uint256 assetId) external view assetExists(assetId) returns (Asset memory) {
        return _assets[assetId];
    }

    function getAssetsByOwner(address owner) external view returns (uint256[] memory) {
        uint256 length = _ownerAssets[owner].length();
        uint256[] memory assetIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            assetIds[i] = _ownerAssets[owner].at(i);
        }
        return assetIds;
    }

    function getAssetOwners() external view returns (address[] memory) {
        uint256 length = _assetOwners.length();
        address[] memory owners = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            owners[i] = _assetOwners.at(i);
        }
        return owners;
    }
}
