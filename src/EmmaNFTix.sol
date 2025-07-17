// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract EmmaNFTix is ERC721, ERC2981, Ownable {
    using Counters for Counters.Counter;

    enum TicketType {
        Regular,
        VIP
    }

    uint256 public nextTicketId;
    uint256 public mintPrice = 0.001 ether;

    struct TicketInfo {
        TicketType ticketType;
        bool claimed;
        bool used;
        uint256 expiry;
    }

    Counters.Counter public _tokenIdCounter;
    mapping(uint256 => bool) public ticketUsed;
    mapping(address => bool) public blacklisted;
    mapping(uint256 => string) public _tokenURIs;
    mapping(uint256 => TicketInfo) public ticketDetails;

    event TicketUsed(uint256 tokenId);
    event AttendanceClaimed(address indexed attendee, uint256 ticketId);
    event TicketMinted(address indexed to, uint256 ticketId, TicketType ticketType);

    constructor() ERC721("NFTixTicket", "NFTIX") {
        _setDefaultRoyalty(msg.sender, 500);
        mintPrice = 0.001 ether;
        nextTicketId = 0;
    }

    modifier notBlacklisted() {
        require(!blacklisted[msg.sender], "You are blacklisted");
        _;
    }

    /// @notice Mint a regular resellable ticket
    function mintRegularTicket(address to) external onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _mint(to, tokenId);
        // solhint-disable-next-line not-rely-on-time
        ticketDetails[tokenId] = TicketInfo(TicketType.Regular, false, false, block.timestamp + 7 days);
        emit TicketMinted(to, tokenId, TicketType.Regular);
        _setTokenURI(tokenId, "ipfs://your-metadata-link");
        _tokenIdCounter.increment();
    }

    /// @notice Mint a non-transferable VIP ticket
    function mintVIPTicket(address to) external onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _mint(to, tokenId);
        // solhint-disable-next-line not-rely-on-time
        ticketDetails[tokenId] = TicketInfo(TicketType.VIP, false, false, block.timestamp + 7 days);
        emit TicketMinted(to, tokenId, TicketType.VIP);
        _tokenIdCounter.increment();
    }

    function claimAttendance(uint256 ticketId) external {
        require(ownerOf(ticketId) == msg.sender, "Not ticket owner");
        require(!ticketDetails[ticketId].claimed, "Already claimed");

        // Use storage to modify the actual mapping
        ticketDetails[ticketId].claimed = true;

        emit AttendanceClaimed(msg.sender, ticketId);
    }

    /// @dev Override transfer logic to block VIP transfers
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from != address(0) && ticketDetails[tokenId].ticketType == TicketType.VIP) {
            revert("VIP tickets are non-transferable");
        }
    }

    /// @notice Mark ticket as used at entry
    function useTicket(uint256 tokenId) external {
        require(_exists(tokenId), "Invalid ticket");
        require(ownerOf(tokenId) == msg.sender, "Not your ticket");
        require(!ticketDetails[tokenId].used, "Ticket already used");
        require(block.timestamp <= ticketDetails[tokenId].expiry, "Ticket expired");

        ticketDetails[tokenId].used = true;
        emit TicketUsed(tokenId);
    }

    function incrementTicketId() public {
        nextTicketId++;
    }

    function markTicketUsed(uint256 tokenId) public {
        ticketUsed[tokenId] = true;
    }

    function blacklist(address user) external onlyOwner {
        blacklisted[user] = true;
    }

    function accessTicket() public view notBlacklisted returns (string memory) {
        return "Access granted";
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function updateBlacklist(address user, bool status) external onlyOwner {
        blacklisted[user] = status;
    }

    /// @notice Get whether ticket is used
    function isTicketUsed(uint256 tokenId) external view returns (bool) {
        return ticketDetails[tokenId].used;
    }

    /// @notice Burn ticket (e.g. after event)
    function burnTicket(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
        delete ticketDetails[tokenId];
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOwner {
        require(_exists(tokenId), "URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    function currentTokenId() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    receive() external payable {}
    fallback() external payable {}
}
