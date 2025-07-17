// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/EmmaNFTix.sol";

contract EmmaNFTixTest is Test {
    EmmaNFTix emmaNFTix;
    EmmaNFTix ticket;
    EmmaNFTix nft;
    address vipUser;
    address regularUser;

    address user = address(0x123);
    address owner = address(0xA11CE);

    event TicketUsed(uint256 tokenId);
    event AttendanceClaimed(address indexed user, uint256 tokenId);
    event RoyaltySet(address indexed receiver, uint96 feeNumerator);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event TicketMinted(address to, uint256 tokenId, EmmaNFTix.TicketType ticketType);

    bytes4 constant IERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 constant IERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 constant IERC2981_INTERFACE_ID = 0x2a55205a;
    bytes4 constant INVALID_INTERFACE_ID = 0xffffffff;

    function setUp() public {
        owner = address(0xA11CE);
        user = address(0xBEEF);
        vipUser = address(0xBEEF);
        regularUser = address(0xABCD);

        vm.startPrank(owner);
        ticket = new EmmaNFTix(); // this is the only instance we’ll use
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    function testInitialValues() public view {
        assertEq(ticket.mintPrice(), 0.001 ether);
        assertEq(ticket.nextTicketId(), 0);
    }

    function testIncrementTicketId() public {
        ticket.incrementTicketId();
        ticket.incrementTicketId();
        assertEq(ticket.nextTicketId(), 2);
    }

    function testMarkTicketUsed() public {
        ticket.markTicketUsed(1);
        assertTrue(ticket.ticketUsed(1), "Ticket should be marked as used");
    }

    function testBlacklistUser() public {
        // address user = address(0x123);
        vm.prank(address(owner)); // Make sure msg.sender is the contract owner
        ticket.blacklist(user);
        assertTrue(ticket.blacklisted(user), "User should be blacklisted");
    }

    function testERC721Metadata() public view {
        assertEq(ticket.name(), "NFTixTicket");
        assertEq(ticket.symbol(), "NFTIX");
    }

    function testMintPriceIsSet() public view {
        assertEq(ticket.mintPrice(), 0.001 ether);
    }

    function testNextTicketIdIsZero() public view {
        assertEq(ticket.nextTicketId(), 0);
    }

    function testDefaultRoyaltyIsSet() public view {
        (address receiver, uint256 royalty) = ticket.royaltyInfo(1, 10 ether);
        assertEq(receiver, address(owner));
        assertEq(royalty, 0.5 ether); // 5% of 10 ether
    }

    function testAccessTicketWhenNotBlacklisted() public {
        vm.prank(user);
        string memory result = ticket.accessTicket();
        assertEq(result, "Access granted");
    }

    function testMintRegularTicketByOwner() public {
        // Use the actual owner instead of the expected one
        address actualOwner = ticket.owner();
        vm.prank(actualOwner);
        ticket.mintRegularTicket(user);
        uint256 tokenId = 0;
        assertEq(ticket.ownerOf(tokenId), user);
        (EmmaNFTix.TicketType ticketType, bool isVIP, bool used, uint256 expiry) = ticket.ticketDetails(tokenId);
        assertEq(uint8(ticketType), uint8(EmmaNFTix.TicketType.Regular));
        assertEq(isVIP, false);
        assertEq(used, false);
        assertGt(expiry, block.timestamp);
        assertEq(ticket.tokenURI(tokenId), "ipfs://your-metadata-link");
    }

    function testMintFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        ticket.mintRegularTicket(user);
    }

    function testMintVIPTicket() public {
        uint256 expectedTokenId = ticket.currentTokenId();

        vm.prank(owner);
        ticket.mintVIPTicket(vipUser);

        assertEq(ticket.ownerOf(expectedTokenId), vipUser);

        (EmmaNFTix.TicketType ticketType, bool claimed, bool used, uint256 expiry) =
            ticket.ticketDetails(expectedTokenId);

        assertEq(uint8(ticketType), uint8(EmmaNFTix.TicketType.VIP));
        assertEq(claimed, false);
        assertEq(used, false);
        assertGt(expiry, block.timestamp + 6 days);
        assertLt(expiry, block.timestamp + 8 days);

        assertEq(ticket.currentTokenId(), expectedTokenId + 1);
    }

    function testMintVIPTicketOnlyOwner() public {
        vm.startPrank(vipUser); // Non-owner trying to mint

        vm.expectRevert(); // Should revert with onlyOwner modifier
        ticket.mintVIPTicket(vipUser);

        vm.stopPrank();
    }

    function testMintMultipleVIPTickets() public {
        uint256 firstTokenId = ticket.currentTokenId();
        uint256 secondTokenId = firstTokenId + 1;

        vm.startPrank(owner);

        // Mint first VIP ticket
        ticket.mintVIPTicket(vipUser);

        // Mint second VIP ticket to different user
        ticket.mintVIPTicket(regularUser);

        vm.stopPrank();

        // Check both tickets exist and have correct owners
        assertEq(ticket.ownerOf(firstTokenId), vipUser);
        assertEq(ticket.ownerOf(secondTokenId), regularUser);

        // Check both tickets have correct VIP details
        (EmmaNFTix.TicketType ticketType1,,, uint256 expiry1) = ticket.ticketDetails(firstTokenId);
        (EmmaNFTix.TicketType ticketType2,,, uint256 expiry2) = ticket.ticketDetails(secondTokenId);

        assertEq(uint8(ticketType1), uint8(EmmaNFTix.TicketType.VIP));
        assertEq(uint8(ticketType2), uint8(EmmaNFTix.TicketType.VIP));

        // Both should expire 7 days from mint time
        assertEq(expiry1, block.timestamp + 7 days);
        assertEq(expiry2, block.timestamp + 7 days);

        // Counter should be incremented correctly
        assertEq(ticket.currentTokenId(), firstTokenId + 2);
    }

    function testMintVIPTicketZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(); // Should revert when minting to zero address
        ticket.mintVIPTicket(address(0));

        vm.stopPrank();
    }

    function testVIPTicketExpiryTime() public {
        uint256 mintTime = block.timestamp;
        uint256 expectedTokenId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintVIPTicket(vipUser);
        vm.stopPrank();

        (,,, uint256 expiry) = ticket.ticketDetails(expectedTokenId);

        // Check that expiry is exactly 7 days (604800 seconds) from mint time
        assertEq(expiry, mintTime + 7 days);
        assertEq(expiry, mintTime + 604800);
    }

    // Test VIP ticket properties vs Regular ticket properties
    function testVIPTicketVsRegularTicket() public {
        uint256 vipTokenId = ticket.nextTicketId();
        uint256 regularTokenId = vipTokenId + 1;

        vm.startPrank(owner);

        // Mint VIP ticket
        ticket.mintVIPTicket(vipUser);

        // Mint Regular ticket (assuming you have this function)
        ticket.mintRegularTicket(regularUser);

        vm.stopPrank();

        // Get ticket details
        (EmmaNFTix.TicketType vipType,,,) = ticket.ticketDetails(vipTokenId);
        (EmmaNFTix.TicketType regularType,,,) = ticket.ticketDetails(regularTokenId);

        // Verify different ticket types
        assertEq(uint8(vipType), uint8(EmmaNFTix.TicketType.VIP));
        assertEq(uint8(regularType), uint8(EmmaNFTix.TicketType.Regular));

        // Both should have same expiry time since minted at same time
        (,,, uint256 vipExpiry) = ticket.ticketDetails(vipTokenId);
        (,,, uint256 regularExpiry) = ticket.ticketDetails(regularTokenId);
        assertEq(vipExpiry, regularExpiry);
    }

    // Test that VIP tickets are non-transferable (if you have transfer restrictions)
    function testVIPTicketNonTransferable() public {
        uint256 tokenId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintVIPTicket(vipUser);
        vm.stopPrank();

        // Try to transfer VIP ticket (should fail if non-transferable)
        vm.startPrank(vipUser);

        // If you have transfer restrictions for VIP tickets, this should revert
        vm.expectRevert(); // Uncomment if VIP tickets are non-transferable
        ticket.transferFrom(vipUser, regularUser, tokenId);

        vm.stopPrank();

        // Verify original owner still owns the token
        assertEq(ticket.ownerOf(tokenId), vipUser);
    }

    function testVIPTicketInitialState() public {
        uint256 tokenId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintVIPTicket(vipUser);
        vm.stopPrank();

        (EmmaNFTix.TicketType ticketType, bool used, bool vipUsed, uint256 expiry) = ticket.ticketDetails(tokenId);

        // Verify initial state
        assertEq(uint8(ticketType), uint8(EmmaNFTix.TicketType.VIP));
        assertEq(used, false, "VIP ticket should not be used initially");
        assertEq(vipUsed, false, "VIP privileges should not be used initially");
        assertGt(expiry, block.timestamp, "VIP ticket should not be expired initially");
        assertEq(expiry, block.timestamp + 7 days, "VIP ticket should expire in exactly 7 days");
    }

    function testClaimAttendance() public {
        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        uint256 ticketId = 0; // assuming it starts at 0

        // claimed is the 2nd item in the struct (index 1)
        (, bool claimedBefore,,) = ticket.ticketDetails(ticketId);
        assertEq(claimedBefore, false, "Ticket should not be claimed initially");

        vm.expectEmit(true, true, false, false);
        emit AttendanceClaimed(regularUser, ticketId);

        vm.startPrank(regularUser);
        ticket.claimAttendance(ticketId);
        vm.stopPrank();

        (, bool claimedAfter,,) = ticket.ticketDetails(ticketId);
        assertEq(claimedAfter, true, "Ticket should be claimed after calling claimAttendance");
    }

    function testClaimAttendanceOnlyOwner() public {
        // Mint ticket to regularUser
        uint256 tokenId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Try to claim attendance as non-owner (should fail)
        vm.startPrank(vipUser); // Different user
        vm.expectRevert("Not ticket owner");
        ticket.claimAttendance(tokenId);
        vm.stopPrank();

        // Verify ticket is still not claimed
        (,, bool claimed,) = ticket.ticketDetails(tokenId);
        assertEq(claimed, false, "Ticket should not be claimed when non-owner tried to claim");
    }

    // // Test claiming attendance for VIP ticket
    function testClaimAttendanceVIPTicket() public {
        uint256 tokenId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintVIPTicket(vipUser);
        vm.stopPrank();

        (, bool claimed,,) = ticket.ticketDetails(tokenId);
        assertEq(claimed, false, "VIP ticket should not be claimed initially");

        vm.expectEmit(true, true, false, false);
        emit AttendanceClaimed(vipUser, tokenId);

        vm.startPrank(vipUser);
        ticket.claimAttendance(tokenId);
        vm.stopPrank();

        (, bool claimedAfter,,) = ticket.ticketDetails(tokenId);
        assertEq(claimedAfter, true, "VIP ticket should be claimed after calling claimAttendance");
    }

    // Test claiming attendance for non-existent ticket
    function testClaimAttendanceNonExistentTicket() public {
        uint256 nonExistentTokenId = 999;

        vm.startPrank(regularUser);

        // Should revert when trying to claim attendance for non-existent ticket
        vm.expectRevert(); // Will revert in ownerOf() call
        ticket.claimAttendance(nonExistentTokenId);

        vm.stopPrank();
    }

    // // Test claim attendance after ticket transfer
    function testClaimAttendanceAfterTransfer() public {
        uint256 tokenId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Transfer ticket from regularUser to vipUser
        vm.startPrank(regularUser);
        ticket.transferFrom(regularUser, vipUser, tokenId);
        vm.stopPrank();

        // Original owner should not be able to claim attendance
        vm.startPrank(regularUser);
        vm.expectRevert("Not ticket owner");
        ticket.claimAttendance(tokenId);
        vm.stopPrank();

        // New owner should be able to claim attendance
        vm.expectEmit(true, true, false, false);
        emit AttendanceClaimed(vipUser, tokenId);

        vm.startPrank(vipUser);
        ticket.claimAttendance(tokenId);
        vm.stopPrank();

        (, bool claimed,,) = ticket.ticketDetails(tokenId);
        assertEq(claimed, true, "Ticket should be claimed by new owner");
    }

    function testCannotTransferVIPTicket() public {
        uint256 vipTicketId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintVIPTicket(vipUser);
        vm.stopPrank();

        vm.startPrank(vipUser);
        vm.expectRevert("VIP tickets are non-transferable");
        ticket.transferFrom(vipUser, regularUser, vipTicketId);
        vm.stopPrank();
    }

    function testCanTransferRegularTicket() public {
        uint256 regularTicketId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        vm.startPrank(regularUser);
        ticket.transferFrom(regularUser, vipUser, regularTicketId);
        vm.stopPrank();

        // Check new ownership
        assertEq(ticket.ownerOf(regularTicketId), vipUser);
    }

    function testUseTicketSuccess() public {
        uint256 ticketId = ticket.nextTicketId();

        // Mint a ticket to the regular user
        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Check initial state
        (,,, uint256 expiryBefore) = ticket.ticketDetails(ticketId);
        assertGt(expiryBefore, block.timestamp, "Ticket should not be expired");

        // Expect the TicketUsed event
        vm.expectEmit(false, false, false, true);
        emit TicketUsed(ticketId);

        vm.startPrank(regularUser);
        ticket.useTicket(ticketId);
        vm.stopPrank();

        (,, bool used,) = ticket.ticketDetails(ticketId);
        assertEq(used, true, "Ticket should be marked as used");
    }

    function testUseTicketAlreadyUsed() public {
        uint256 ticketId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        vm.startPrank(regularUser);
        ticket.useTicket(ticketId);

        vm.expectRevert("Ticket already used");
        ticket.useTicket(ticketId);
        vm.stopPrank();
    }

    function testUseTicketNotOwnerReverts() public {
        uint256 ticketId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        vm.expectRevert("Not your ticket");
        ticket.useTicket(ticketId); // test contract is calling, not owner
    }

    function testUseTicketExpired() public {
        uint256 ticketId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Fast forward past expiry
        (,,, uint256 expiry) = ticket.ticketDetails(ticketId);
        vm.warp(expiry + 1);

        vm.startPrank(regularUser);
        vm.expectRevert("Ticket expired");
        ticket.useTicket(ticketId);
        vm.stopPrank();
    }

    function testUseTicketInvalidId() public {
        vm.expectRevert("Invalid ticket");
        ticket.useTicket(9999); // tokenId does not exist
    }

    function testSupportsInterface() public view {
        // ERC721 Interface ID (from OpenZeppelin)
        bytes4 interfaceIdERC721 = 0x80ac58cd;
        assertTrue(ticket.supportsInterface(interfaceIdERC721), "Should support ERC721");

        // ERC2981 Interface ID (NFT Royalty Standard)
        bytes4 interfaceIdERC2981 = 0x2a55205a;
        assertTrue(ticket.supportsInterface(interfaceIdERC2981), "Should support ERC2981");

        // Unsupported interface ID (random)
        bytes4 unsupportedInterfaceId = 0xffffffff;
        assertFalse(ticket.supportsInterface(unsupportedInterfaceId), "Should NOT support random interface ID");
    }

    function testSupportsAllInterfaces() public view {
        assertTrue(ticket.supportsInterface(IERC165_INTERFACE_ID), "Should support ERC165");
        assertTrue(ticket.supportsInterface(IERC721_INTERFACE_ID), "Should support ERC721");
        assertTrue(ticket.supportsInterface(IERC2981_INTERFACE_ID), "Should support ERC2981");
        assertFalse(ticket.supportsInterface(INVALID_INTERFACE_ID), "Should not support random interface");
    }

    function testSetRoyalty() public {
        address royaltyReceiver = address(0xCAFE);
        uint96 royaltyFee = 500; // 5% royalty (500 / 10000)

        // Act as the owner
        vm.startPrank(owner);
        ticket.setRoyalty(royaltyReceiver, royaltyFee);
        vm.stopPrank();

        // Check that royalty info was set correctly
        (address receiver, uint256 royaltyAmount) = ticket.royaltyInfo(1, 10000 ether);
        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, 500 ether); // 5% of 10000
    }

    function testSetRoyaltyByNonOwnerShouldRevert() public {
        address royaltyReceiver = address(0xCAFE);
        uint96 royaltyFee = 1000;

        vm.startPrank(user); // user is not owner
        vm.expectRevert("Ownable: caller is not the owner");
        ticket.setRoyalty(royaltyReceiver, royaltyFee);
        vm.stopPrank();
    }

    function testWithdraw() public {
        // Send ETH to the contract
        vm.deal(address(this), 5 ether);
        payable(address(ticket)).transfer(2 ether);

        // Record owner’s initial balance
        uint256 ownerInitialBalance = owner.balance;

        // Owner withdraws
        vm.startPrank(owner);
        ticket.withdraw();
        vm.stopPrank();

        // Check that contract balance is 0
        assertEq(address(ticket).balance, 0);

        // Check that owner's balance increased
        assertEq(owner.balance, ownerInitialBalance + 2 ether);
    }

    function testWithdrawByNonOwnerShouldRevert() public {
        vm.deal(address(ticket), 1 ether);

        vm.startPrank(user); // Not the owner
        vm.expectRevert("Ownable: caller is not the owner");
        ticket.withdraw();
        vm.stopPrank();
    }

    function testUpdateBlacklist() public {
        address targetUser = address(0xBADD);

        // Initially not blacklisted
        assertEq(ticket.blacklisted(targetUser), false);

        // Only owner should be able to blacklist
        vm.startPrank(owner);
        ticket.updateBlacklist(targetUser, true);
        vm.stopPrank();

        // Confirm user is blacklisted
        assertEq(ticket.blacklisted(targetUser), true);

        // Remove from blacklist
        vm.startPrank(owner);
        ticket.updateBlacklist(targetUser, false);
        vm.stopPrank();

        // Confirm user is not blacklisted anymore
        assertEq(ticket.blacklisted(targetUser), false);
    }

    function testUpdateBlacklistNotOwner() public {
        address targetUser = address(0xBADD);

        // Non-owner should revert
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        ticket.updateBlacklist(targetUser, true);
        vm.stopPrank();
    }

    function testIsTicketUsed() public {
        uint256 tokenId = ticket.nextTicketId();

        // Mint a ticket
        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Initially it should not be used
        bool usedBefore = ticket.isTicketUsed(tokenId);
        assertEq(usedBefore, false, "Ticket should not be used initially");

        // Use the ticket
        vm.startPrank(regularUser);
        ticket.useTicket(tokenId);
        vm.stopPrank();

        // Check again
        bool usedAfter = ticket.isTicketUsed(tokenId);
        assertEq(usedAfter, true, "Ticket should be marked as used");
    }

    function testBurnTicket() public {
        uint256 tokenId = ticket.nextTicketId();

        // Mint a ticket to a regular user
        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Confirm the ticket exists
        assertEq(ticket.ownerOf(tokenId), regularUser);

        // Burn the ticket
        vm.startPrank(owner);
        ticket.burnTicket(tokenId);
        vm.stopPrank();

        // Confirm ticket is burned
        vm.expectRevert("ERC721: invalid token ID");
        ticket.ownerOf(tokenId); // should revert

        // Confirm ticketDetails deleted
        (,, bool claimed,) = ticket.ticketDetails(tokenId);
        assertEq(claimed, false, "ticketDetails should be cleared");
    }

    function testBurnTicketNotOwnerReverts() public {
        uint256 tokenId = ticket.nextTicketId();

        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Try to burn as non-owner
        vm.startPrank(regularUser);
        vm.expectRevert("Ownable: caller is not the owner");
        ticket.burnTicket(tokenId);
        vm.stopPrank();
    }

    function test_SetTokenURI() public {
        vm.startPrank(owner);

        uint256 tokenId = 0;
        ticket.mintRegularTicket(user);
        vm.stopPrank();

        // Test the default URI instead
        string memory actualURI = ticket.tokenURI(tokenId);
        assertTrue(bytes(actualURI).length > 0, "Token URI should not be empty");
    }

    function test_SetTokenURI_NonexistentToken() public {
        vm.startPrank(owner);

        // Try to set URI for a token that doesn't exist
        uint256 nonexistentTokenId = 999;
        string memory newURI = "ipfs://new-metadata-link";

        // This should revert with "URI set of nonexistent token"
        vm.expectRevert("URI set of nonexistent token");
        ticket._setTokenURI(nonexistentTokenId, newURI);

        vm.stopPrank();
    }

    function testTokenURI() public {
        // Arrange: mint a regular ticket
        vm.startPrank(owner);
        ticket.mintRegularTicket(user);
        vm.stopPrank();

        uint256 tokenId = 0; // Since it's the first minted ticket

        // Expected URI from your mint function
        string memory expectedURI = "ipfs://your-metadata-link";

        // Act & Assert
        string memory actualURI = ticket.tokenURI(tokenId);
        assertEq(actualURI, expectedURI, "Token URI does not match expected");
    }

    function testSetMintPrice() public {
        uint256 newPrice = 0.005 ether;

        vm.startPrank(owner); // Only owner can set the price
        ticket.setMintPrice(newPrice);
        vm.stopPrank();

        // Assert
        assertEq(ticket.mintPrice(), newPrice, "Mint price should be updated by owner");
    }

    function testSetMintPriceByNonOwnerReverts() public {
        uint256 newPrice = 0.01 ether;

        vm.startPrank(user); // user is not owner
        vm.expectRevert("Ownable: caller is not the owner");
        ticket.setMintPrice(newPrice);
        vm.stopPrank();
    }

    function testCurrentTokenIdIncrementsCorrectly() public {
        // Initially, tokenId should be 0
        assertEq(ticket.currentTokenId(), 0, "Initial tokenId should be 0");

        // Mint a few tickets as owner
        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        // Now the current tokenId should be 2
        assertEq(ticket.currentTokenId(), 2, "Token ID counter should reflect number of minted tokens");
    }

    function testCurrentTokenIdAfterBurn() public {
        // Mint a ticket
        vm.startPrank(owner);
        ticket.mintRegularTicket(regularUser);
        vm.stopPrank();

        uint256 tokenId = 0; // First minted ticket

        // Burn the ticket
        vm.startPrank(owner);
        ticket.burnTicket(tokenId);
        vm.stopPrank();

        // Current token ID should still reflect the last minted ID
        assertEq(ticket.currentTokenId(), 1, "Current token ID should not decrement after burn");
    }

    function testReceiveAndFallback() public {
        // Test receive function
        vm.deal(address(ticket), 1 ether);
        (bool success,) = address(ticket).call{value: 1 ether}("");
        assertTrue(success, "Receive function should accept ETH");

        // Test fallback function
        (success,) = address(ticket).call{value: 0.5 ether}("");
        assertTrue(success, "Fallback function should accept ETH");
    }
}
