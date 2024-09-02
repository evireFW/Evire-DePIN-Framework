// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract DePINManager is Ownable, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

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
    EnumerableSet.AddressSet private _assetOwners;
    mapping(address => EnumerableSet.UintSet) private _ownerAssets;

    event AssetCreated(uint256 indexed assetId, string name, address indexed owner);
    event AssetUpdated(uint256 indexed assetId, string metadataURI, address indexed owner);
    event AssetTransferred(uint256 indexed assetId, address indexed from, address indexed to);
    event AssetDeactivated(uint256 indexed assetId, address indexed owner);
    event AssetReactivated(uint256 indexed assetId, address indexed owner);

    modifier onlyAssetOwner(uint256 assetId) {
        require(_assets[assetId].owner == msg.sender, "Caller is not the asset owner");
        _;
    }

    modifier assetExists(uint256 assetId) {
        require(_assets[assetId].owner != address(0), "Asset does not exist");
        _;
    }

    constructor() {
        _assetCounter = 0;
    }

    function createAsset(string memory name, string memory metadataURI) external whenNotPaused returns (uint256) {
        _assetCounter = _assetCounter.add(1);
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

    function updateAsset(uint256 assetId, string memory metadataURI) external whenNotPaused assetExists(assetId) onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        asset.metadataURI = metadataURI;
        asset.updatedAt = block.timestamp;

        emit AssetUpdated(assetId, metadataURI, msg.sender);
    }

    function transferAsset(uint256 assetId, address to) external whenNotPaused assetExists(assetId) onlyAssetOwner(assetId) {
        require(to != address(0), "Invalid recipient address");

        address previousOwner = _assets[assetId].owner;
        _assets[assetId].owner = to;
        _ownerAssets[previousOwner].remove(assetId);
        _ownerAssets[to].add(assetId);

        if (_ownerAssets[previousOwner].length() == 0) {
            _assetOwners.remove(previousOwner);
        }

        _assetOwners.add(to);

        emit AssetTransferred(assetId, previousOwner, to);
    }

    function deactivateAsset(uint256 assetId) external whenNotPaused assetExists(assetId) onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        require(asset.active, "Asset is already deactivated");
        asset.active = false;

        emit AssetDeactivated(assetId, msg.sender);
    }

    function reactivateAsset(uint256 assetId) external whenNotPaused assetExists(assetId) onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        require(!asset.active, "Asset is already active");
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
