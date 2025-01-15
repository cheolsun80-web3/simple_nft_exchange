// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "../src/NftExchangeV2.sol";

contract CounterScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        IWOVER wover = IWOVER(0x59c914C8ac6F212bb655737CC80d9Abc79A1e273);
        IERC721 nethers = IERC721(address(0x6f969f215E77bEaeC5c92b3344BddbCe8DA67604));
        NftExchangeV2 nftexchange = new NftExchangeV2(wover);
        nftexchange.addNft(nethers);
        vm.stopBroadcast();
    }
}
