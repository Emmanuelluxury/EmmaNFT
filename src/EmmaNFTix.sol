// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// @title EmmaNFTix
// @notice A smart contract for managing NFT tickets with different types, minting, claiming attendance, and royalty support.
// @dev This contract allows minting of regular and VIP tickets, claiming attendance
contract EmmaNFTix is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    /// @notice Enum to define ticket types
    /// @dev Regular tickets are resellable, VIP tickets are non-transferable
    enum TicketType {
        Regular,
        VIP
    }

    /// @notice Next ticket ID to be minted
    /// @dev This is used to keep track of the next available ticket ID
    uint256 public nextTicketId;
    uint256 public mintPrice = 0.001 ether;
    uint256 public constant maxSupply = 1000;

    /// @notice Struct to hold ticket information
    /// @dev Contains ticket type, claimed status, used status, and expiry time
    struct TicketInfo {
        TicketType ticketType;
        bool claimed;
        bool used;
        uint256 expiry;
    }

    /// @notice Counter for token IDs
    /// @dev Used to generate unique token IDs for each ticket
    Counters.Counter public _tokenIdCounter;
    mapping(uint256 => bool) public ticketUsed;
    mapping(address => bool) public blacklisted;
    mapping(uint256 => string) public _tokenURIs;
    mapping(uint256 => TicketInfo) public ticketDetails;

    // @notice Event emitted when a ticket is minted
    // @param to The address that receives the minted ticket
    // @param tokenId The ID of the minted ticket
    // @param ticketType The type of the minted ticket (Regular or VIP)
    // @dev This event is emitted when a new ticket is minted
    event Received(address, uint256);
    event TicketUsed(uint256 tokenId);
    event BlacklistUpdated(address user, bool status);
    event AttendanceClaimed(address indexed attendee, uint256 ticketId);
    event TicketMinted(address indexed to, uint256 ticketId, TicketType ticketType);

    /// @notice Constructor to initialize the contract
    /// @dev Sets the contract name, symbol, default royalty, and initial mint price
    constructor() ERC721("EmmaNFTix", "NFTix") {
        _setDefaultRoyalty(msg.sender, 500);
        mintPrice = 0.001 ether;
        nextTicketId = 0;
    }

    /// @notice Modifier to check if the caller is not blacklisted
    /// @dev This modifier ensures that only non-blacklisted users can call certain functions
    /// @dev Reverts if the caller is blacklisted
    modifier notBlacklisted() {
        require(!blacklisted[msg.sender], "You are blacklisted");
        _;
    }

    /// @notice Mint a regular resellable ticket
    function mintRegularTicket(address to) external onlyOwner {
        require(_tokenIdCounter.current() < maxSupply, "Max supply reached");
        uint256 tokenId = _tokenIdCounter.current();
        _mint(to, tokenId);
        // solhint-disable-next-line not-rely-on-time
        ticketDetails[tokenId] = TicketInfo(TicketType.Regular, false, false, block.timestamp + 7 days);
        emit TicketMinted(to, tokenId, TicketType.Regular);
        _setTokenURI(tokenId, "ipfs://bafkreig3oz6qvfxjgbuq56wedqicdfpmza7ep2hmuxtd3k26v4q6femism");
        _tokenIdCounter.increment();
    }

    /// @notice Mint a non-transferable VIP ticket
    function mintVIPTicket(address to) external onlyOwner {
        require(_tokenIdCounter.current() < maxSupply, "Max supply reached");
        uint256 tokenId = _tokenIdCounter.current();
        _mint(to, tokenId);
        // solhint-disable-next-line not-rely-on-time
        ticketDetails[tokenId] = TicketInfo(TicketType.VIP, false, false, block.timestamp + 7 days);
        emit TicketMinted(to, tokenId, TicketType.VIP);
        _tokenIdCounter.increment();
    }

    /// @notice Claim attendance for a ticket
    /// @dev This function allows the ticket owner to claim attendance for their ticket
    /// @param ticketId The ID of the ticket for which attendance is being claimed
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

    /// @notice Increment the next ticket ID
    /// @dev This function is used to update the next available ticket ID
    /// @dev It can be called by the owner to ensure the next ticket ID is unique
    function incrementTicketId() public {
        nextTicketId++;
    }

    /// @notice Mark a ticket as used
    /// @dev This function is used to mark a ticket as used, typically after entry
    function markTicketUsed(uint256 tokenId) public {
        ticketUsed[tokenId] = true;
    }

    /// @notice Blacklist a user
    /// @dev This function allows the owner to blacklist a user, preventing them from accessing certain
    function blacklist(address user) external onlyOwner {
        blacklisted[user] = true;

        emit AttendanceClaimed(user, 0);
    }

    /// @notice Remove a user from the blacklist
    /// @dev This function allows the owner to remove a user from the blacklist, allowing them
    function accessTicket() public view notBlacklisted returns (string memory) {
        return "Access granted";
    }

    /// @notice Check if a user is blacklisted
    /// @dev This function allows anyone to check if a user is blacklisted
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Withdraw contract balance to owner
    /// @dev This function allows the owner to withdraw the contract's balance
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /// @notice Update blacklist status for a user
    /// @dev This function allows the owner to update the blacklist status of a user
    function updateBlacklist(address user, bool status) external onlyOwner {
        blacklisted[user] = status;
    }

    /// @notice Get whether ticket is used
    function isTicketUsed(uint256 tokenId) external view returns (bool) {
        return ticketDetails[tokenId].used;
    }

    /// @notice Burn ticket (e.g. after event)
    function burnTicket(uint256 tokenId) external onlyOwner {
        require(ownerOf(tokenId) == msg.sender || msg.sender == owner(), "Not authorized");
        _burn(tokenId);
        delete ticketDetails[tokenId];
    }

    /// @notice Set the token URI for a specific token ID
    /// @dev This function allows the owner to set the metadata URI for a specific token ID
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOwner {
        require(!ticketDetails[tokenId].used, "Cannot update URI after ticket is used");
        require(_exists(tokenId), "URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /// @notice Get the token URI for a specific token ID
    /// @dev This function returns the metadata URI for a specific token ID
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }

    /// @notice Set the mint price for tickets
    /// @dev This function allows the owner to update the mint price for tickets
    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    /// @notice Get the current token ID counter
    /// @dev This function returns the current value of the token ID counter
    function currentTokenId() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable {}
}
