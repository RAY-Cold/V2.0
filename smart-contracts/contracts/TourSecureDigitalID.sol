// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * TourSecure Digital ID (Soulbound)
 *
 * - EIP-5192 (Minimal Soulbound NFTs): locked(...) always true
 * - One token per address (account-bound)
 * - Non-transferable: block transfers by overriding _update (OZ v5 pattern)
 * - Stores only hash + URI (keep PII off-chain)
 */

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC5192 /* is IERC721 */ {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);
    function locked(uint256 tokenId) external view returns (bool);
}

contract TourSecureDigitalID is ERC721, Ownable, IERC5192 {
    error NonTransferable();
    error AlreadyIssued();
    error InvalidToken();
    error NotHolderOrIssuer();
    error RevokedToken();

    struct Record {
        bytes32 idHash;       // keccak256 of off-chain JSON (no PII on-chain)
        string  metadataURI;  // IPFS/Supabase URL (may be signed)
        uint64  issuedAt;
        uint64  updatedAt;
        bool    revoked;
    }

    uint256 private _nextId; // simple auto-increment (OZ v5: no Counters)
    mapping(uint256 => Record) public records;
    mapping(address => uint256) public tokenOf; // address => tokenId (0 if none)

    // true  = holder OR issuer can update metadata (default)
    // false = issuer (owner) only
    bool public holderCanUpdate = true;

    constructor(address initialOwner)
        ERC721("TourSecure Digital ID", "TSDID")
        Ownable(initialOwner) // OZ v5: pass owner
    {}

    // -------- Soulbound enforcement (OZ v5) --------
    // Block transfers but allow mint (from == 0) and optional burn (to == 0).
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId); // zero if minting
        if (from != address(0) && to != address(0)) {
            revert NonTransferable();     // transfer attempt -> block
        }
        return super._update(to, tokenId, auth);
    }

    // -------- EIP-5192 --------
    function locked(uint256 tokenId) external view override returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert InvalidToken();
        return true; // always locked (soulbound)
    }

    // -------- Issue / Update / Revoke --------

    /// Mint a Digital ID to `to`. One per address.
    function issue(address to, bytes32 idHash, string calldata metadataURI)
        external
        onlyOwner
        returns (uint256 tokenId)
    {
        if (tokenOf[to] != 0) revert AlreadyIssued();

        tokenId = ++_nextId;
        _safeMint(to, tokenId);

        records[tokenId] = Record({
            idHash: idHash,
            metadataURI: metadataURI,
            issuedAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp),
            revoked: false
        });

        tokenOf[to] = tokenId;

        emit Locked(tokenId);
        emit MetadataUpdated(tokenId, idHash, metadataURI);
    }

    /// Update hash/URI (holder OR issuer by default).
    function update(uint256 tokenId, bytes32 newHash, string calldata newURI) external {
        if (_ownerOf(tokenId) == address(0)) revert InvalidToken();

        bool isHolder = msg.sender == ownerOf(tokenId);
        bool isIssuer = msg.sender == owner();
        if (!(isIssuer || (holderCanUpdate && isHolder))) revert NotHolderOrIssuer();

        Record storage r = records[tokenId];
        if (r.revoked) revert RevokedToken();

        r.idHash = newHash;
        r.metadataURI = newURI;
        r.updatedAt = uint64(block.timestamp);

        emit MetadataUpdated(tokenId, newHash, newURI);
    }

    /// Revoke token (keeps on-chain audit; frontends should treat as invalid).
    function revoke(uint256 tokenId) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert InvalidToken();
        records[tokenId].revoked = true;
        emit Revoked(tokenId);
        // Optional: enable burn on revoke by uncommenting:
        // _burn(tokenId);
        // tokenOf[ownerOf(tokenId)] = 0;
    }

    function setHolderCanUpdate(bool allowed) external onlyOwner {
        holderCanUpdate = allowed;
        emit HolderUpdatePermissionChanged(allowed);
    }

    // -------- Views --------

    function getRecord(uint256 tokenId) external view returns (Record memory) {
        if (_ownerOf(tokenId) == address(0)) revert InvalidToken();
        return records[tokenId];
    }

    function identityOf(address user) external view returns (bool exists, uint256 tokenId, bool revoked) {
        tokenId = tokenOf[user];
        exists = tokenId != 0 && _ownerOf(tokenId) != address(0);
        revoked = exists ? records[tokenId].revoked : false;
    }

    function verify(address user, bytes32 expectedHash) external view returns (bool ok) {
        uint256 tid = tokenOf[user];
        if (tid == 0 || _ownerOf(tid) == address(0)) return false;
        Record storage r = records[tid];
        if (r.revoked) return false;
        return r.idHash == expectedHash;
    }

    // EIP-165 (includes ERC721 + IERC5192)
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    // -------- Events --------
    event MetadataUpdated(uint256 indexed tokenId, bytes32 idHash, string metadataURI);
    event Revoked(uint256 indexed tokenId);
    event HolderUpdatePermissionChanged(bool allowed);
}
