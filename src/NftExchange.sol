// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// import IERC721 from OpenZeppelin
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// import Ownable from OpenZeppelin
import "@openzeppelin/contracts/access/Ownable.sol";

// import Pausable from OpenZeppelin
import "@openzeppelin/contracts/utils/Pausable.sol";

// import address from OpenZeppelin
import "@openzeppelin/contracts/utils/Address.sol";

// import ReentrancyGuard from OpenZeppelin
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract NftExchange is Ownable, Pausable, ReentrancyGuardTransient {
    constructor() Ownable(msg.sender) Pausable() {
    }
}