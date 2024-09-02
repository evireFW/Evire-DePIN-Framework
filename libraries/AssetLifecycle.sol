// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AssetLifecycle is ERC721Enumerable, Ownable, Pausable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _assetIdCounter;

    struct Asset {
        uint256 id;
        string metadataURI;
        address owner;
        bool isFrozen;
        uint256 creationTime;
        uint256 lastTransferTime;
    }

    mapping(uint256 => Asset) private assets;

    event AssetCreated(uint256 indexed assetId, address indexed owner, string metadataURI);
    event AssetTransferred(uint256 indexed assetId, address indexed from, address indexed to);
    event AssetFrozen(uint256 indexed assetId);
    event AssetUnfrozen(uint256 indexed assetId);
    event AssetDestroyed(uint256 indexed assetId);

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function createAsset(string memory metadataURI) external whenNotPaused returns (uint256) {
        _assetIdCounter.increment();
        uint256 newAssetId = _assetIdCounter.current();

        _mint(msg.sender, newAssetId);

        assets[newAssetId] = Asset({
            id: newAssetId,
            metadataURI: metadataURI,
            owner: msg.sender,
            isFrozen: false,
            creationTime: block.timestamp,
            lastTransferTime: block.timestamp
        });

        emit AssetCreated(newAssetId, msg.sender, metadataURI);

        return newAssetId;
    }

    function transferAsset(address to, uint256 assetId) external whenNotPaused nonReentrant {
        require(ownerOf(assetId) == msg.sender, "AssetLifecycle: transfer of asset that is not own");
        require(!assets[assetId].isFrozen, "AssetLifecycle: asset is frozen");

        _transfer(msg.sender, to, assetId);

        assets[assetId].owner = to;
        assets[assetId].lastTransferTime = block.timestamp;

        emit AssetTransferred(assetId, msg.sender, to);
    }

    function freezeAsset(uint256 assetId) external onlyOwner {
        require(_exists(assetId), "AssetLifecycle: freeze for nonexistent asset");
        require(!assets[assetId].isFrozen, "AssetLifecycle: asset already frozen");

        assets[assetId].isFrozen = true;

        emit AssetFrozen(assetId);
    }

    function unfreezeAsset(uint256 assetId) external onlyOwner {
        require(_exists(assetId), "AssetLifecycle: unfreeze for nonexistent asset");
        require(assets[assetId].isFrozen, "AssetLifecycle: asset is not frozen");

        assets[assetId].isFrozen = false;

        emit AssetUnfrozen(assetId);
    }

    function destroyAsset(uint256 assetId) external onlyOwner whenNotPaused nonReentrant {
        require(_exists(assetId), "AssetLifecycle: destroy for nonexistent asset");

        _burn(assetId);
        delete assets[assetId];

        emit AssetDestroyed(assetId);
    }

    function getAssetDetails(uint256 assetId) external view returns (Asset memory) {
        require(_exists(assetId), "AssetLifecycle: query for nonexistent asset");

        return assets[assetId];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
