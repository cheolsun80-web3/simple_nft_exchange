// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {NftExchange} from "../src/NftExchange.sol";
import {Nft} from "../src/Nft.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NftExchangeTest is Test {
    NftExchange nftExchange;
    IERC721 nftA;
    IERC721 nftB;

    address userA = vm.addr(1);
    address userB = vm.addr(2);

    function setUp() public {
        nftExchange = new NftExchange();

        nftA = new Nft();
        nftB = new Nft();
        
        nftExchange.addNft(nftA);
        nftExchange.addNft(nftB);

        vm.label(userA, "userA");
        vm.label(userB, "userB");
    }

    function testAddNft() public {
        assertEq(address(nftExchange.nfts(0)), address(nftA));
        assertEq(address(nftExchange.nfts(1)), address(nftB));
    }
}
