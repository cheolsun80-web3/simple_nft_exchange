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

// import WOVER
import "./WOVER.sol";

// import BidLib
import "./BidLib.sol";

contract NftExchange is Ownable, Pausable, ReentrancyGuardTransient {
    using BidLib for BidLib.Heap;

    struct Ask {
        address seller;
        uint256 price;
        uint256 idx;
        uint256 expiration;
    }

    mapping(IERC721 => bool) public whitelist;
    IERC721[] public nfts;
    uint256 public fee; // 100 = 1%
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant DEL = type(uint256).max;

    uint256 public constant MAX_ASKS = 100;
    uint256 public constant MAX_BIDS = 100;

    IWOVER public immutable WETH;

    uint256 public expiration;
    mapping(IERC721 => BidLib.Heap) internal bids;
    mapping(IERC721 => uint256) public bidsOffset;
    
    mapping(IERC721 => Ask[]) public asks;
    mapping(IERC721 => uint256) public asksOffset;

    mapping(address => uint256) public nonces;
    mapping(address => uint256) public balances;

    enum BidState {
        None,
        Bid,
        Success,
        Cancel
    }
    struct BidInfo {
        IERC721 nft;
        uint256 nonce;
        BidState state;
    }
    mapping(address => BidInfo[]) public bidInfos;

    struct AskInfo {
        IERC721 nft;
        uint256 idx;
        uint256 price;
        uint256 bn;
    }
    mapping(address => AskInfo[]) public askInfos;

    uint256 public feeBalance;

    mapping(IERC721 => mapping(uint256 => bool)) public tokenLocks;

    event NftAdded(IERC721 nft);
    event NftRemoved(IERC721 nft);
    event FeeChanged(uint256 fee);
    event ExpirationChanged(uint256 expiration);

    event BidAdded(IERC721 nft, uint256 tokenId, address bidder, uint256 price, uint256 expiration);
    event BidRemoved(IERC721 nft, uint256 tokenId, address bidder, uint256 price);

    event AskAdded(IERC721 nft, uint256 tokenId, address seller, uint256 price, uint256 expiration);
    event AskRemoved(IERC721 nft, uint256 tokenId, address seller, uint256 price);

    event Trade(IERC721 nft, uint256 tokenId, address seller, address buyer, uint256 price);

    event FeeWithdrawn(uint256 amount);

    constructor(IWOVER wover) Ownable(msg.sender) Pausable() {
        WETH = wover;
        setFee(300);
        setExpiration(7 days);
    }

    receive() external payable {
        require(msg.sender == address(WETH), "Only WETH");
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
        emit FeeChanged(fee);
    }

    function setExpiration(uint256 _expiration) public onlyOwner {
        expiration = _expiration;
        emit ExpirationChanged(expiration);
    }

    function addNft(IERC721 nft) public onlyOwner {
        require(!whitelist[nft], "NFT already whitelisted");
        // check NFT Interface
        require(nft.supportsInterface(type(IERC721).interfaceId), "NFT does not support IERC721");
        whitelist[nft] = true;
        nfts.push(nft);

        bids[nft].init();
        emit NftAdded(nft);
    }

    function removeNft(IERC721 nft) public onlyOwner {
        require(whitelist[nft], "NFT not whitelisted");
        whitelist[nft] = false;
        for (uint256 i = 0; i < nfts.length; i++) {
            if (nfts[i] == nft) {
                nfts[i] = nfts[nfts.length - 1];
                nfts.pop();
                break;
            }
        }
        emit NftRemoved(nft);
    }

    modifier onlyWhitelisted(IERC721 nft) {
        require(whitelist[nft], "NFT not whitelisted");
        _;
    }

    modifier onlyEOA() {
        // require(!Address.isContract(msg.sender), "Only EOA");
        // require(msg.sender == tx.origin, "Only EOA - 1");
        require(address(msg.sender).code.length == 0, "Only EOA - 2");
        _;
    }

    function _cleanup_ask(IERC721 nft) internal {
        Ask[] storage _asks = asks[nft];
        uint256 _offset = asksOffset[nft];
        for (uint256 i = _offset; i < _asks.length; i++) {
            if (_asks[i].expiration > block.timestamp) {
                asksOffset[nft] = i;
                break;
            }
            tokenLocks[nft][_asks[i].idx] = false;
        }
    }

    function _cleanup_ask_deep(IERC721 nft) internal {
        Ask[] storage _asks = asks[nft];
        uint256 _offset = asksOffset[nft];
        for (uint256 i = _offset; i < _asks.length; i++) {
            if (_asks[i].expiration > block.timestamp) {
                asksOffset[nft] = i;
                break;
            }
            tokenLocks[nft][_asks[i].idx] = false;
        }
        
        _offset = asksOffset[nft];
        for (uint256 i = _offset; i < _asks.length; i++) {
            if (IERC721(nft).ownerOf(_asks[i].idx) != _asks[i].seller) {
                emit AskRemoved(nft, _asks[i].idx, _asks[i].seller, _asks[i].price);
                tokenLocks[nft][_asks[i].idx] = false;
                _asks[i].seller = address(0);
                _asks[i].price = DEL;
                _asks[i].idx = DEL;
                continue;
            }
            if (IERC721(nft).getApproved(_asks[i].idx) != address(this)) {
                emit AskRemoved(nft, _asks[i].idx, _asks[i].seller, _asks[i].price);
                tokenLocks[nft][_asks[i].idx] = false;
                _asks[i].seller = address(0);
                _asks[i].price = DEL;
                _asks[i].idx = DEL;
            }
        }
    }

    function addAsk(IERC721 nft, uint256 tokenId, uint256 price) public whenNotPaused onlyWhitelisted(nft) onlyEOA nonReentrant {
        _cleanup_ask(nft);

        if (tokenLocks[nft][tokenId]) {
            Ask[] storage _asks = asks[nft];
            for (uint i = asksOffset[nft]; i < _asks.length; i++) {
                if (_asks[i].idx == tokenId) {
                    if (_asks[i].seller != msg.sender) { // when token owner changes
                        emit AskRemoved(nft, _asks[i].idx, _asks[i].seller, _asks[i].price);
                        tokenLocks[nft][tokenId] = false;
                        _asks[i].seller = address(0);
                        _asks[i].price = DEL;
                        _asks[i].idx = DEL;
                    }
                    break;
                }
            }
        }
        require(!tokenLocks[nft][tokenId], "Token locked");
        // check approval
        require(nft.getApproved(tokenId) == address(this), "Not approved");

        // check owner
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        
        // check max asks
        require((asks[nft].length - asksOffset[nft]) < MAX_ASKS, "Too many asks");

        tokenLocks[nft][tokenId] = true;
        
        // check price
        require(price > 1 ether, "Price too low");
        require((price % 1 ether) == 0, "Price not multiple of 1 ether");

        asks[nft].push(Ask({
            seller: msg.sender,
            price: price,
            idx: tokenId,
            expiration: block.timestamp + expiration
        }));

        emit AskAdded(nft, tokenId, msg.sender, price, block.timestamp + expiration);
    }

    function _removeAsk(IERC721 nft, uint256 tokenId, bool requireVerify) internal {
        require(tokenLocks[nft][tokenId], "Token not locked");
        uint256 idx;
        for (idx = asksOffset[nft]; idx < asks[nft].length; idx++) {
            if (asks[nft][idx].idx == tokenId) {
                break;
            }
        }
        require(asks[nft][idx].idx == tokenId, "Ask not found");
        if (requireVerify) {
            require(asks[nft][idx].seller == msg.sender, "Not seller");
        }
        emit AskRemoved(nft, tokenId, msg.sender, asks[nft][idx].price);

        tokenLocks[nft][tokenId] = false;
        asks[nft][idx].seller = address(0);
        asks[nft][idx].price = DEL;
        asks[nft][idx].idx = DEL;
    }

    function removeAsk(IERC721 nft, uint256 tokenId) public whenNotPaused onlyWhitelisted(nft) onlyEOA nonReentrant {
        _cleanup_ask(nft);
        _removeAsk(nft, tokenId, true);
    }

    function acceptAsk(IERC721 nft, uint256 tokenId, uint256 price) public payable {
        require(msg.value == price, "Value mismatch");
        uint balance = WETH.balanceOf(address(this));
        WETH.deposit{value: price}();
        require(WETH.balanceOf(address(this)) == balance + price, "Deposit failed");
        _acceptAsk(nft, tokenId, price, true);
    }

    function acceptAskWETH(IERC721 nft, uint256 tokenId, uint256 maxPrice) public {
        _acceptAsk(nft, tokenId, maxPrice, false);
    }

    function _acceptAsk(IERC721 nft, uint256 tokenId, uint256 maxPrice, bool isPayable) internal whenNotPaused onlyWhitelisted(nft) onlyEOA nonReentrant {
        _cleanup_ask(nft);
        uint256 idx;
        for (idx = asksOffset[nft]; idx < asks[nft].length; idx++) {
            if (asks[nft][idx].idx == tokenId) {
                break;
            }
        }

        Ask memory ask = asks[nft][idx];

        require(ask.idx == tokenId, "Ask not found");
        require(ask.expiration > block.timestamp, "Ask expired"); // double check
        require(ask.price == maxPrice, "Price error"); // anti MEV

        _removeAsk(nft, tokenId, false);

        // transfer NFT
        nft.safeTransferFrom(ask.seller, msg.sender, tokenId);

        // transfer WETH

        if (!isPayable) {
            uint balance = WETH.balanceOf(address(this));
            WETH.transferFrom(msg.sender, address(this), ask.price);
            require(WETH.balanceOf(address(this)) == balance + ask.price, "Transfer failed");
        }

        uint price = ask.price;
        uint feeAmount = price * fee / FEE_DENOMINATOR;
        
        feeBalance += feeAmount;
        WETH.transfer(ask.seller, price - feeAmount);

        emit Trade(nft, tokenId, ask.seller, msg.sender, price);

        askInfos[ask.seller].push(AskInfo({
            nft: nft,
            idx: tokenId,
            price: price,
            bn: block.number
        }));
    }

    function addBidWETH(IERC721 nft, uint256 price) public {
        _addBid(nft, price, false);
    }

    function addBid(IERC721 nft, uint256 price) public payable {
        require(msg.value == price, "Value mismatch");
        uint balance = WETH.balanceOf(address(this));
        WETH.deposit{value: price}();
        require(WETH.balanceOf(address(this)) == balance + price, "Deposit failed");
        _addBid(nft, price, true);
    }

    function _addBid(IERC721 nft, uint256 price, bool isPayable) internal whenNotPaused onlyWhitelisted(nft) onlyEOA nonReentrant {
        require(price > 1 ether, "Price too low");
        require((price % 1 ether) == 0, "Price not multiple of 1 ether");

        // get top bid
        (, uint256 topPrice) = bids[nft].getMax();
        require(price > topPrice, "Price too low");

        uint _nonce = nonces[msg.sender]++;

        if (!isPayable) {
            // transfer WETH
            uint256 balance = WETH.balanceOf(msg.sender);
            WETH.transferFrom(msg.sender, address(this), price);
            require(WETH.balanceOf(msg.sender) == balance - price, "Transfer failed");
        }

        // insert bid
        BidLib.Heap storage _bids = bids[nft];
        _bids.insert(BidLib.Bidder(msg.sender, _nonce), price);
        emit BidAdded(nft, _nonce, msg.sender, price, block.timestamp + expiration);

        bidInfos[msg.sender].push(BidInfo({
            nft: nft,
            nonce: _nonce,
            state: BidState.Bid
        }));
    }

    function removeBidWETH(IERC721 nft, uint256 nonce) public whenNotPaused onlyWhitelisted(nft) onlyEOA nonReentrant {
        BidLib.Heap storage _bids = bids[nft];
        uint idx = _bids.getBidIndexByAddressAndNonce(msg.sender, nonce);
        require(idx != 0, "Bid not found");

        (BidLib.Bid memory bid) = _bids.getBidAtIndex(idx);
        require(bid.bidder.bidder == msg.sender, "Not bidder");
        require(bid.bidder.nonce == nonce, "Nonce mismatch");

        _bids.removeAtIndex(idx);
        emit BidRemoved(nft, nonce, msg.sender, bid.price);

        for (uint i = 0; i < bidInfos[msg.sender].length; i++) {
            if (bidInfos[msg.sender][i].nft == nft && bidInfos[msg.sender][i].nonce == nonce) {
                bidInfos[msg.sender][i].state = BidState.Cancel;
                break;
            }
        }
        
        // refund WETH
        WETH.transfer(msg.sender, bid.price);
    }

    function removeBid(IERC721 nft, uint256 nonce) public whenNotPaused onlyWhitelisted(nft) onlyEOA nonReentrant {
        BidLib.Heap storage _bids = bids[nft];
        uint idx = _bids.getBidIndexByAddressAndNonce(msg.sender, nonce);
        require(idx != 0, "Bid not found");

        (BidLib.Bid memory bid) = _bids.getBidAtIndex(idx);
        require(bid.bidder.bidder == msg.sender, "Not bidder");
        require(bid.bidder.nonce == nonce, "Nonce mismatch");

        _bids.removeAtIndex(idx);
        emit BidRemoved(nft, nonce, msg.sender, bid.price);

        for (uint i = 0; i < bidInfos[msg.sender].length; i++) {
            if (bidInfos[msg.sender][i].nft == nft && bidInfos[msg.sender][i].nonce == nonce) {
                bidInfos[msg.sender][i].state = BidState.Cancel;
                break;
            }
        }

        // refund WETH
        WETH.withdraw(bid.price);
        require(address(this).balance == bid.price, "Withdraw failed");
        (bool success,) = msg.sender.call{value: bid.price, gas: 3333}('');
        require(success, "Withdraw failed");
    }

    function acceptBid(IERC721 nft, uint256 tokenId, uint256 minPrice) public whenNotPaused onlyWhitelisted(nft) onlyEOA nonReentrant {
        _cleanup_ask(nft);
        // check owner and approval
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(nft.getApproved(tokenId) == address(this), "Not approved");

        // get top bid
        (BidLib.Bidder memory bidder, uint256 price) = bids[nft].extractMax();
        require(price > 0, "No bid");

        require(price == minPrice, "Price error"); // anti MEV

        if (tokenLocks[nft][tokenId]) {
            _removeAsk(nft, tokenId, false);
        }

        // transfer NFT
        nft.safeTransferFrom(msg.sender, bidder.bidder, tokenId);


        uint feeAmount = price * fee / FEE_DENOMINATOR;
        feeBalance += feeAmount;

        // transfer WETH
        WETH.withdraw(price - feeAmount);
        require(address(this).balance == price - feeAmount, "Withdraw failed");
        (bool success,) = msg.sender.call{value: price - feeAmount, gas: 3333}('');
        require(success, "Withdraw failed");

        emit BidRemoved(nft, bidder.nonce, bidder.bidder, price);
        emit Trade(nft, tokenId, msg.sender, bidder.bidder, price);
    }
}