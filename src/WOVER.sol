// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IWOVER {
    function deposit() external payable;
    function withdraw(uint256 wad) external;

    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);
    error ERC20InvalidReceiver(address);

    // ERC20
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function balanceOf(address guy) external view returns (uint256);
    function allowance(address src, address dst) external view returns (uint256);

    function approve(address spender, uint256 wad) external returns (bool);
    function transfer(address dst, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);

    event Approval(address indexed src, address indexed dst, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    // ERC-165
    function supportsInterface(bytes4 interfaceID) external view returns (bool);

    // ERC-2612
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract WOVER is IWOVER {
    string public constant name = "Wrapped Over";
    string public constant symbol = "WOVER";
    uint8 public constant decimals = 18;

    bytes32 private immutable PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes4 private immutable MAGICVALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)")); // 0x1626ba7e

    bytes32 private immutable _DOMAIN_SEPARATOR;
    uint256 public immutable deploymentChainId;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    mapping(address => uint256) public override nonces;

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        deploymentChainId = chainId;
        _DOMAIN_SEPARATOR = _calculateDomainSeparator(chainId);
    }

    receive() external payable {
        deposit();
    }

    // MODIFIER
    modifier ensuresRecipient(address to) {
        // Prevents from burning or sending WETH tokens to the contract.
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        if (to == address(this)) {
            revert ERC20InvalidReceiver(address(this));
        }
        _;
    }

    // VIEW
    function supportsInterface(bytes4 interfaceID) external pure override returns (bool) {
        return interfaceID == this.supportsInterface.selector // ERC-165
            || interfaceID == this.permit.selector; // ERC-2612
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId == deploymentChainId ? _DOMAIN_SEPARATOR : _calculateDomainSeparator(chainId);
    }

    function totalSupply() external view override returns (uint256) {
        return address(this).balance;
    }

    // STATE MODIFIYING
    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function deposit() public payable {
        require(msg.value > 0, "Deposit must be greater than 0");
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 value) external override {
        require(value > 0, "Withdrawal must be greater than 0");
        balanceOf[msg.sender] -= value;
        (bool success,) = msg.sender.call{value: value}("");
        require(success, "Withdrawal failed");
        emit Transfer(msg.sender, address(0), value);
    }

    function transfer(address to, uint256 value) external override ensuresRecipient(to) returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value)
        external
        override
        ensuresRecipient(to)
        returns (bool)
    {
        if (from != msg.sender) {
            uint256 _allowance = allowance[from][msg.sender];
            if (_allowance != type(uint256).max) {
                allowance[from][msg.sender] -= value;
            }
        }

        balanceOf[from] -= value;
        balanceOf[to] += value;

        emit Transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address signer = ECDSA.recover(digest, v, r, s);
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    // PRIVATE
    function _calculateDomainSeparator(uint256 chainId) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }
}
