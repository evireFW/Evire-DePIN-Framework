// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AssetLifecycle is ERC721Enumerable, Ownable(msg.sender), Pausable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _assetIdCounter;

    struct Asset {
        uint256 id;
        string metadataURI;
        bool isFrozen;
        uint256 creationTime;
        uint256 lastTransferTime;
    }

    struct MaintenanceRecord {
        uint256 date;
        string description;
    }

    mapping(uint256 => Asset) private assets;
    mapping(uint256 => MaintenanceRecord[]) private maintenanceRecords;

    event AssetCreated(uint256 indexed assetId, address indexed owner, string metadataURI);
    event MetadataURIUpdated(uint256 indexed assetId, string metadataURI);
    event AssetFrozen(uint256 indexed assetId);
    event AssetUnfrozen(uint256 indexed assetId);
    event AssetDestroyed(uint256 indexed assetId);
    event MaintenanceRecordAdded(uint256 indexed assetId, uint256 date, string description);

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    // New function to check if an asset exists
    function assetExists(uint256 assetId) public view returns (bool) {
        return assets[assetId].creationTime != 0;
    }

    function createAsset(string memory metadataURI) external whenNotPaused returns (uint256) {
        _assetIdCounter.increment();
        uint256 newAssetId = _assetIdCounter.current();

        _mint(msg.sender, newAssetId);

        assets[newAssetId] = Asset({
            id: newAssetId,
            metadataURI: metadataURI,
            isFrozen: false,
            creationTime: block.timestamp,
            lastTransferTime: block.timestamp
        });

        emit AssetCreated(newAssetId, msg.sender, metadataURI);

        return newAssetId;
    }

    function updateMetadataURI(uint256 assetId, string memory newMetadataURI) external whenNotPaused {
        require(assetExists(assetId), "AssetLifecycle: update for nonexistent asset");
        require(ownerOf(assetId) == msg.sender, "AssetLifecycle: caller is not the asset owner");

        assets[assetId].metadataURI = newMetadataURI;

        emit MetadataURIUpdated(assetId, newMetadataURI);
    }

    function addMaintenanceRecord(uint256 assetId, string memory description) external whenNotPaused {
        require(assetExists(assetId), "AssetLifecycle: maintenance for nonexistent asset");
        require(ownerOf(assetId) == msg.sender, "AssetLifecycle: caller is not the asset owner");

        maintenanceRecords[assetId].push(MaintenanceRecord({
            date: block.timestamp,
            description: description
        }));

        emit MaintenanceRecordAdded(assetId, block.timestamp, description);
    }

    function getMaintenanceRecords(uint256 assetId) external view returns (MaintenanceRecord[] memory) {
        require(assetExists(assetId), "AssetLifecycle: query for nonexistent asset");
        return maintenanceRecords[assetId];
    }

    function freezeAsset(uint256 assetId) external whenNotPaused {
        require(assetExists(assetId), "AssetLifecycle: freeze for nonexistent asset");
        require(!assets[assetId].isFrozen, "AssetLifecycle: asset already frozen");
        require(ownerOf(assetId) == msg.sender || msg.sender == owner(), "AssetLifecycle: caller is not asset owner or contract owner");

        assets[assetId].isFrozen = true;

        emit AssetFrozen(assetId);
    }

    function unfreezeAsset(uint256 assetId) external whenNotPaused {
        require(assetExists(assetId), "AssetLifecycle: unfreeze for nonexistent asset");
        require(assets[assetId].isFrozen, "AssetLifecycle: asset is not frozen");
        require(ownerOf(assetId) == msg.sender || msg.sender == owner(), "AssetLifecycle: caller is not asset owner or contract owner");

        assets[assetId].isFrozen = false;

        emit AssetUnfrozen(assetId);
    }

    function destroyAsset(uint256 assetId) external whenNotPaused nonReentrant {
        require(assetExists(assetId), "AssetLifecycle: destroy for nonexistent asset");
        require(ownerOf(assetId) == msg.sender || msg.sender == owner(), "AssetLifecycle: caller is not asset owner or contract owner");

        _burn(assetId);
        delete assets[assetId];
        delete maintenanceRecords[assetId];

        emit AssetDestroyed(assetId);
    }

    function transferAsset(address to, uint256 assetId) external whenNotPaused nonReentrant {
        safeTransferFrom(msg.sender, to, assetId);
    }

    function getAssetDetails(uint256 assetId) external view returns (Asset memory) {
        require(assetExists(assetId), "AssetLifecycle: query for nonexistent asset");
        return assets[assetId];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Updated _beforeTokenTransfer function
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 /*batchSize*/) internal virtual {
    

        if (from != address(0) && to != address(0)) {
            require(!assets[tokenId].isFrozen, "AssetLifecycle: asset is frozen");
            assets[tokenId].lastTransferTime = block.timestamp;
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}