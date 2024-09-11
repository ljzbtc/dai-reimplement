// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Spotter Contract
 * @dev This contract is part of a decentralized finance (DeFi) system, likely for a stablecoin or lending platform.
 * 
 * Key functionalities:
 * 1. Price Feed Management: Manages price feeds (oracles) for different collateral types.
 * 2. Liquidation Ratio Setting: Allows setting of liquidation ratios for each collateral type.
 * 3. Spot Price Calculation: Calculates and updates the spot price for collateral, considering:
 *    - The current price from the oracle
 *    - The par value (reference price per DAI)
 *    - The liquidation ratio
 * 4. Vat (CDP Engine) Interaction: Updates the spot price in the Vat contract, which is likely the core
 *    contract managing Collateralized Debt Positions (CDPs) or vaults.
 * 5. Access Control: Implements basic access control with 'wards' for administrative functions.
 * 6. Emergency Shutdown: Includes a 'cage' function to disable critical functionality in emergencies.
 * 
 * This contract plays a crucial role in maintaining the stability and security of the DeFi system
 * by ensuring accurate and up-to-date collateral valuations for lending or minting operations.
 */
interface VatLike {
    function file(bytes32, bytes32, uint) external;
}

interface PipLike {
    function peek() external returns (bytes32, bool);
}

contract Spotter {
    // --- Auth ---
    mapping(address => uint) public wards;
    function rely(address guy) external auth {
        wards[guy] = 1;
    }
    function deny(address guy) external auth {
        wards[guy] = 0;
    }
    modifier auth() {
        require(wards[msg.sender] == 1, "Spotter/not-authorized");
        _;
    }

    // --- Data ---
    struct Ilk {
        PipLike pip; // Price Feed
        uint256 mat; // Liquidation ratio [ray]
    }

    // every collateral type has a price feed and a liquidation ratio
    mapping(bytes32 => Ilk) public ilks;

    VatLike public vat; // CDP Engine
    uint256 public par; // ref per dai [ray] a unit of currency

    uint256 public live;

    // --- Events ---
    event Poke(
        bytes32 ilk,
        bytes32 val, // [wad]
        uint256 spot // [ray]
    );

    // --- Init ---
    constructor(address vat_) {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        par = ONE;
        live = 1;
    }

    // --- Math ---
    uint constant ONE = 10 ** 27;

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, ONE) / y;
    }

    // --- Administration ---
    function file(bytes32 ilk, bytes32 what, address pip_) external auth {
        require(live == 1, "Spotter/not-live");
        // set the price feed for the collateral type
        if (what == "pip") ilks[ilk].pip = PipLike(pip_);
        else revert("Spotter/file-unrecognized-param");
    }
    function file(bytes32 what, uint data) external auth {
        require(live == 1, "Spotter/not-live");
        // set the ref per dai
        if (what == "par") par = data;
        else revert("Spotter/file-unrecognized-param");
    }
    function file(bytes32 ilk, bytes32 what, uint data) external auth {
        require(live == 1, "Spotter/not-live");

        // set liquidation ratio
        if (what == "mat") ilks[ilk].mat = data;
        else revert("Spotter/file-unrecognized-param");
    }

    // --- Update value ---
    function poke(bytes32 ilk) external {
        (bytes32 val, bool has) = ilks[ilk].pip.peek();

        /*
        uint256 spot;
        if (has) {
            uint256 adjustedPrice = mul(uint(val), 10 ** 9);
            uint256 priceInDai = rdiv(adjustedPrice, par);
            spot = rdiv(priceInDai, ilks[ilk].mat);
        } else {
            spot = 0;
        }
        */
        uint256 spot = has
            ? rdiv(rdiv(mul(uint(val), 10 ** 9), par), ilks[ilk].mat)
            : 0;
        vat.file(ilk, "spot", spot);
        emit Poke(ilk, val, spot);
    }

    function cage() external auth {
        live = 0;
    }
}
