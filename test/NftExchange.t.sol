// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {NftExchange} from "../src/NftExchange.sol";
import {Nft} from "../src/Nft.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {WOVER, IWOVER} from "../src/WOVER.sol";

contract NftExchangeTest is Test {
    WOVER WETH;
    NftExchange nftExchange;
    Nft nftA;
    Nft nftB;

    address userA = vm.addr(1);
    address userB = vm.addr(2);

    function setUp() public {
        /// Deploy a mock WETH token
        WETH = new WOVER();

        /// Deploy the NftExchange, passing in the WETH
        nftExchange = new NftExchange(IWOVER(address(WETH)));

        /// Deploy two mock NFT contracts
        nftA = new Nft();
        nftB = new Nft();

        /// Add them to the exchange’s whitelist
        nftExchange.addNft(nftA);
        nftExchange.addNft(nftB);

        /// Sanity checks
        assertEq(address(nftExchange.nfts(0)), address(nftA));
        assertEq(address(nftExchange.nfts(1)), address(nftB));

        /// Label addresses in the test environment
        vm.label(userA, "UserA");
        vm.label(userB, "UserB");

        /// Give userB some Ether and WETH to simulate a buyer with funds
        vm.deal(userB, 1100 ether);

        /// Convert some of userB’s ETH to WETH
        vm.prank(userB);
        WETH.deposit{value: 100 ether}();
        assertEq(WETH.balanceOf(address(userB)), 100 ether);
    }

    /// @dev Tests adding a new NFT to the whitelist
    function testAddNft() public {
        IERC721 nftC = new Nft();
        nftExchange.addNft(nftC);
        assertEq(address(nftExchange.nfts(2)), address(nftC));
    }

    /// @dev Tests removing an NFT from the whitelist
    function testRemoveNft() public {
        // Remove nftA, so nftB should now occupy index 0 in the array
        nftExchange.removeNft(nftA);
        assertEq(address(nftExchange.nfts(0)), address(nftB));
    }

    /// @dev Tests updating the fee percentage
    function testSetFee() public {
        nftExchange.setFee(100);
        assertEq(nftExchange.fee(), 100);
    }

    /// @dev Tests updating the default expiration time
    function testSetExpiration() public {
        nftExchange.setExpiration(100);
        assertEq(nftExchange.expiration(), 100);
    }

    /// @dev Tests adding an ask order
    function testAddAsk() public {
        /// Mint an NFT to userA
        nftA.mint(userA, 1);

        /// Approve the NftExchange to transfer userA’s token
        vm.startPrank(userA, userA);
        nftA.approve(address(nftExchange), 1);

        /// Add ask for 100 ether
        nftExchange.addAsk(nftA, 1, 100 ether);

        /// Check that ask is stored correctly
        (address seller, uint256 price, uint256 tokenId, uint256 expiration) = nftExchange.asks(nftA, 0);
        assertEq(seller, userA, "Seller should be userA");
        assertEq(price, 100 ether, "Price should be 100 ether");
        assertEq(tokenId, 1, "TokenId should be 1");
        assertEq(expiration, block.timestamp + nftExchange.expiration(), "Expiration should be currentTime + default");
        vm.stopPrank();
    }

    /// @dev Tests removing an ask order
    function testRemoveAsk() public {
        /// Mint NFT and add an ask
        nftA.mint(userA, 2);
        vm.startPrank(userA, userA);
        nftA.approve(address(nftExchange), 2);
        nftExchange.addAsk(nftA, 2, 50 ether);

        /// Sanity check
        (address sellerBefore, uint256 priceBefore,,) = nftExchange.asks(nftA, 0);
        assertEq(sellerBefore, userA, "Seller should be userA before removal");
        assertEq(priceBefore, 50 ether, "Price should be 50 ether before removal");

        /// Remove the ask
        nftExchange.removeAsk(nftA, 2);

        /// After removal, the ask data is "marked" as removed internally
        // We cannot read the array’s length easily because it only grows,
        // but we can check the fields for the removed index.
        (address sellerAfter, uint256 priceAfter, uint256 idxAfter,) = nftExchange.asks(nftA, 0);
        // The contract sets these fields to special sentinel values (`DEL`) to indicate removal.
        // So a direct assertion can be done if your contract sets them to `type(uint256).max`.
        // For clarity, we just check they are not valid anymore.
        assertEq(sellerAfter, address(0), "Seller should be cleared");
        assertEq(priceAfter, type(uint256).max, "Price should be set to DEL");
        assertEq(idxAfter, type(uint256).max, "Token id should be set to DEL");
        vm.stopPrank();
    }

    /// @dev Tests accepting an ask (i.e., userB buys NFT from userA)
    function testAcceptAskWETH() public {
        /// Step 1: userA mints an NFT and places an ask
        nftA.mint(userA, 10);
        vm.startPrank(userA, userA);
        nftA.approve(address(nftExchange), 10);
        nftExchange.addAsk(nftA, 10, 30 ether);
        vm.stopPrank();

        /// Step 2: userB attempts to buy (accept ask)
        /// userB has WETH = 100 ether (from setUp), but `acceptAsk` requires that the buyer
        /// transfer that cost in WETH to the contract. We must ensure userB has enough WETH
        /// or performs a deposit if needed. For simplicity, userB already has WETH.

        vm.startPrank(userB, userB);

        // userB approves the NftExchange to transfer WETH
        WETH.approve(address(nftExchange), 30 ether);
        // The function signature is: acceptAskWETH(IERC721 nft, uint256 tokenId, uint256 maxPrice)
        // The ask was 30 ether. We pass a maxPrice of 30 ether or more to prevent reverts.
        nftExchange.acceptAskWETH(nftA, 10, 30 ether);

        vm.stopPrank();

        /// Step 3: Validate that userB now owns the token
        assertEq(nftA.ownerOf(10), userB, "UserB should own NFT #10 after purchase");

        // Additionally, you might want to check the fee has accrued to feeBalance
        // (depending on your exact logic for fee distribution).
        uint256 expectedFee = (30 ether * nftExchange.fee()) / nftExchange.FEE_DENOMINATOR();
        assertEq(nftExchange.feeBalance(), expectedFee, "Fee balance mismatch");
    }

    /// @dev Tests accepting an ask (i.e., userB buys NFT from userA)
    function testAcceptAsk() public {
        /// Step 1: userA mints an NFT and places an ask
        nftA.mint(userA, 20);
        vm.startPrank(userA, userA);
        nftA.approve(address(nftExchange), 20);
        nftExchange.addAsk(nftA, 20, 30 ether);
        vm.stopPrank();

        /// Step 2: userB attempts to buy (accept ask)
        /// userB has WETH = 100 ether (from setUp), but `acceptAsk` requires that the buyer
        /// transfer that cost in WETH to the contract. We must ensure userB has enough WETH
        /// or performs a deposit if needed. For simplicity, userB already has WETH.

        vm.startPrank(userB, userB);

        // The function signature is: acceptAsk(IERC721 nft, uint256 tokenId, uint256 maxPrice)
        // The ask was 30 ether. We pass a maxPrice of 30 ether or more to prevent reverts.
        nftExchange.acceptAsk{value: 30 ether}(nftA, 20, 30 ether);

        vm.stopPrank();

        /// Step 3: Validate that userB now owns the token
        assertEq(nftA.ownerOf(20), userB, "UserB should own NFT #20 after purchase");

        // Additionally, you might want to check the fee has accrued to feeBalance
        // (depending on your exact logic for fee distribution).
        uint256 expectedFee = (30 ether * nftExchange.fee()) / nftExchange.FEE_DENOMINATOR();
        assertEq(nftExchange.feeBalance(), expectedFee, "Fee balance mismatch");
    }
}
