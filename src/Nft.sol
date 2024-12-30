// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Nft is ERC721 {
    constructor() ERC721("Nft", "NFT") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
