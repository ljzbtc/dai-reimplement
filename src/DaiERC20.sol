// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// dai.sol -- Dai Stablecoin ERC-20 Token

/*

Modified variable names:

Changed the decimals constant to uppercase DECIMALS to comply with constant naming conventions.
Renamed internal functions add and sub to _add and _sub, using the underscore prefix to denote internal functions.


Adjusted structure:

Added section comments (such as // Auth, // ERC20 Data, etc.) to organize the code structure.
Rearranged functions to follow the recommended contract layout order.
Added blank lines between functions to improve readability.
Standardized indentation and formatting for better consistency.


Preserved function names:

Except for the internal math functions, all other function names remain unchanged.
Main ERC20 functions (like transfer, transferFrom, approve, etc.) and other custom functions (such as mint, burn, push, pull, move) kept their original names.

*/



contract Dai {
    ///////////////////
    // Auth
    ///////////////////
    mapping(address => uint256) public wards;

    function rely(address to) external auth {
        wards[to] = 1;
    }

    function deny(address to) external auth {
        wards[to] = 0;
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "Dai/not-authorized");
        _;
    }

    ///////////////////
    // ERC20 Data
    ///////////////////
    string public constant name = "Dai Stablecoin";
    string public constant symbol = "DAI";
    string public constant version = "1";
    uint8 public constant DECIMALS = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    ///////////////////
    // Events
    ///////////////////
    event Approval(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    ///////////////////
    // EIP712
    ///////////////////
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor(uint256 chainId_) {
        wards[msg.sender] = 1;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId_,
                address(this)
            )
        );
    }

    ///////////////////
    // Math
    ///////////////////
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "Dai/add-overflow");
    }

    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Dai/sub-underflow");
    }

    ///////////////////
    // Token Functions
    ///////////////////
    function transfer(address to, uint256 amount) external returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Dai/insufficient-balance");

        if (from != msg.sender && allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Dai/insufficient-allowance");
            allowance[from][msg.sender] = _sub(allowance[from][msg.sender], amount);
        }

        balanceOf[from] = _sub(balanceOf[from], amount);
        balanceOf[to] = _add(balanceOf[to], amount);

        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address usr, uint256 amount) external auth {
        balanceOf[usr] = _add(balanceOf[usr], amount);
        totalSupply = _add(totalSupply, amount);
        emit Transfer(address(0), usr, amount);
    }

    function burn(address usr, uint256 amount) external {
        require(balanceOf[usr] >= amount, "Dai/insufficient-balance");

        if (usr != msg.sender && allowance[usr][msg.sender] != type(uint256).max) {
            require(allowance[usr][msg.sender] >= amount, "Dai/insufficient-allowance");
            allowance[usr][msg.sender] = _sub(allowance[usr][msg.sender], amount);
        }
        balanceOf[usr] = _sub(balanceOf[usr], amount);
        totalSupply = _sub(totalSupply, amount);
        emit Transfer(usr, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    ///////////////////
    // Alias Functions
    ///////////////////
    function push(address usr, uint256 amount) external {
        transferFrom(msg.sender, usr, amount);
    }

    function pull(address usr, uint256 amount) external {
        transferFrom(usr, msg.sender, amount);
    }

    function move(address from, address to, uint256 amount) external {
        transferFrom(from, to, amount);
    }

    ///////////////////
    // Permit
    ///////////////////
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, holder, spender, nonce, expiry, allowed))
            )
        );

        require(holder != address(0), "Dai/invalid-address-0");
        require(holder == ecrecover(digest, v, r, s), "Dai/invalid-permit");
        require(expiry == 0 || block.timestamp <= expiry, "Dai/permit-expired");
        require(nonce == nonces[holder]++, "Dai/invalid-nonce");
        uint256 amount = allowed ? type(uint256).max : 0;
        allowance[holder][spender] = amount;
        emit Approval(holder, spender, amount);
    }
}