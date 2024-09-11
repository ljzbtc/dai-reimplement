// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Vault Contract
 * @dev This contract implements a complex vault system for managing collateralized debt positions (CDPs).
 * 
 * Key features:
 * 1. Authorization system (wards) for administrative actions
 * 2. Permission system (can) for users to delegate actions
 * 3. Management of different collateral types (ilks)
 * 4. Tracking of user vaults (urns) with collateral and debt
 * 5. Debt ceiling management for individual collateral types and the entire system
 * 6. CDP manipulation (frob) for adjusting collateral and debt
 * 7. CDP transfer between users (fork)
 * 8. Emergency shutdown capability (cage)
 * 9. Collateral and stablecoin accounting
 * 10. Rate adjustments for different collateral types
 * 11. System debt management (heal, suck)
 * 
 * This contract serves as the core of a decentralized lending platform, allowing users to lock up
 * collateral and generate stablecoin debt against it, while maintaining system-wide stability and
 * individual vault safety.
 */
contract Vault {
    // --- Auth ---
    mapping(address => uint) public wards;
    function rely(address usr) external auth {
        require(live == 1, "Vat/not-live");
        wards[usr] = 1;
    }
    function deny(address usr) external auth {
        require(live == 1, "Vat/not-live");
        wards[usr] = 0;
    }
    modifier auth() {
        require(wards[msg.sender] == 1, "Vat/not-authorized");
        _;
    }

    // use mapping to store the permissions can be rename to permissions
    mapping(address => mapping(address => uint)) public can;
    // give the permission to usr to act on behalf of msg.sender
    function hope(address usr) external {
        can[msg.sender][usr] = 1;
    }

    // remove the permission to usr to act on behalf of msg.sender can be rename to removePermission
    function nope(address usr) external {
        can[msg.sender][usr] = 0;
    }

    // check if the usr has the permission to act on behalf of bit can be rename to isAllowed
    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    // --- Data ---
    // Isolated Collateral Kind
    struct Ilk {
        uint256 Art; // Total Normalised Debt     [wad] can be rename to totalDebt
        uint256 rate; // Accumulated Rates         [ray] can be rename to accumulatedRate
        uint256 spot; // Price with Safety Margin  [ray] can be rename to price
        uint256 line; // Debt Ceiling              [rad] can be rename to debtCeiling
        uint256 dust; // Urn Debt Floor            [rad] minimum debt have worth to maintain
    }
    struct Urn {
        uint256 ink; // Locked Collateral  [wad] Urn: a specific Vault.
        uint256 art; // Normalised Debt    [wad] normalized outstanding stablecoin debt.
    }

    mapping(bytes32 => Ilk) public ilks; // why bytes32 do the mapping
    mapping(bytes32 => mapping(address => Urn)) public urns; // why bytes32 do the mapping
    mapping(bytes32 => mapping(address => uint)) public gem; // [wad]
    mapping(address => uint256) public dai; // [rad]
    mapping(address => uint256) public sin; // sin: unbacked stablecoin (system debt, not belonging to any urn).

    uint256 public debt; // Total Dai Issued    [rad]
    uint256 public vice; // Total Unbacked Dai  [rad] sum of all sin
    uint256 public Line; // Total Debt Ceiling  [rad]
    uint256 public live; // Active Flag // protocol is live or not flag

    // --- Init ---
    constructor() {
        wards[msg.sender] = 1; // msg.sender is the owner of the contract
        live = 1; // protocol is live
    }

    // --- Math ---  // safe math functions    it can be remove
    function _add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function _sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function _mul(uint x, int y) internal pure returns (int z) {
        z = int(x) * y;
        require(int(x) >= 0);
        require(y == 0 || z / y == int(x));
    }
    function _add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function _sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function _mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---

    // create a new collateral type only owner can do this
    function init(bytes32 ilk) external auth {
        require(ilks[ilk].rate == 0, "Vat/ilk-already-init"); // if the collateral type is already initialized then revert
        ilks[ilk].rate = 10 ** 27; // set the rate to 10 ** 27  why? this a standrd value
    }

    // set the debt ceiling for the whole protocol
    function file(bytes32 what, uint data) external auth {
        require(live == 1, "Vat/not-live");
        if (what == "Line") Line = data;
        else revert("Vat/file-unrecognized-param");
    }

    // set the spot price for a specific collateral type it can use enum instead of bytes32
    function file(bytes32 ilk, bytes32 what, uint data) external auth {
        require(live == 1, "Vat/not-live");
        if (what == "spot") ilks[ilk].spot = data;
        else if (what == "line") ilks[ilk].line = data;
        else if (what == "dust") ilks[ilk].dust = data;
        else revert("Vat/file-unrecognized-param");
    }

    // stop the protocol
    function cage() external auth {
        live = 0;
    }

    //

    // ollateral gem is assigned to users with slip. this auth should be engine to control the collateral because it have the permission to change the collateral
    function slip(bytes32 ilk, address usr, int256 wad) external auth {
        gem[ilk][usr] = _add(gem[ilk][usr], wad);
    }

    // transfer collateral from one user to another why need this? because the engine need to control the collateral
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        require(wish(src, msg.sender), "Vat/not-allowed");
        gem[ilk][src] = _sub(gem[ilk][src], wad);
        gem[ilk][dst] = _add(gem[ilk][dst], wad);
    }

    function move(address src, address dst, uint256 rad) external {
        require(wish(src, msg.sender), "Vat/not-allowed");
        dai[src] = _sub(dai[src], rad);
        dai[dst] = _add(dai[dst], rad);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := or(x, y)
        }
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := and(x, y)
        }
    }

    // --- CDP Manipulation ---
    function frob(
        bytes32 i,
        address u,
        address v,
        address w,
        int dink,
        int dart
    ) external {
        // system is live
        // check if the system is live 
        require(live == 1, "Vat/not-live");


        // get the urn and ilk information  
        // get user's debt  information and collateral information
        Urn memory urn = urns[i][u];

        // get this kind of collateral information
        Ilk memory ilk = ilks[i];
        // ilk has been initialised

        // check if the collateral type is initialized
        require(ilk.rate != 0, "Vat/ilk-not-init");

        
        // increase the collateral or debt  user can mint dai or burn dai
        urn.ink = _add(urn.ink, dink);
        urn.art = _add(urn.art, dart);
        ilk.Art = _add(ilk.Art, dart);

        int dtab = _mul(ilk.rate, dart);
        uint tab = _mul(ilk.rate, urn.art);

        // calculate the total debt 
        debt = _add(debt, dtab);

        // either debt has decreased, or debt ceilings are not exceeded
        require(
            either(
                dart <= 0,
                both(_mul(ilk.Art, ilk.rate) <= ilk.line, debt <= Line)
            ),
            "Vat/ceiling-exceeded"
        );
        // urn is either less risky than before, or it is safe
        require(
            either(both(dart <= 0, dink >= 0), tab <= _mul(urn.ink, ilk.spot)),
            "Vat/not-safe"
        );

        // urn is either more safe, or the owner consents
        require(
            either(both(dart <= 0, dink >= 0), wish(u, msg.sender)),
            "Vat/not-allowed-u"
        );
        // collateral src consents
        require(either(dink <= 0, wish(v, msg.sender)), "Vat/not-allowed-v");
        // debt dst consents
        require(either(dart >= 0, wish(w, msg.sender)), "Vat/not-allowed-w");

        // urn has no debt, or a non-dusty amount

        // they have minimum debt or the debt is not dust
    
        require(either(urn.art == 0, tab >= ilk.dust), "Vat/dust");

        gem[i][v] = _sub(gem[i][v], dink);
        dai[w] = _add(dai[w], dtab);

        urns[i][u] = urn;
        ilks[i] = ilk;
    }
    // --- CDP Fungibility ---

    // transfer valut between two user
    function fork(
        bytes32 ilk,
        address src,
        address dst,
        int dink,
        int dart
    ) external {
        Urn storage u = urns[ilk][src];
        Urn storage v = urns[ilk][dst];
        Ilk storage i = ilks[ilk];

        u.ink = _sub(u.ink, dink);
        u.art = _sub(u.art, dart);
        v.ink = _add(v.ink, dink);
        v.art = _add(v.art, dart);

        uint utab = _mul(u.art, i.rate);
        uint vtab = _mul(v.art, i.rate);

        // both sides consent
        require(
            both(wish(src, msg.sender), wish(dst, msg.sender)),
            "Vat/not-allowed"
        );

        // both sides safe
        require(utab <= _mul(u.ink, i.spot), "Vat/not-safe-src");
        require(vtab <= _mul(v.ink, i.spot), "Vat/not-safe-dst");

        // both sides non-dusty
        require(either(utab >= i.dust, u.art == 0), "Vat/dust-src");
        require(either(vtab >= i.dust, v.art == 0), "Vat/dust-dst");
    }
    // --- CDP Confiscation ---
    function grab(
        bytes32 i,
        address u,
        address v,
        address w,
        int dink,
        int dart
    ) external auth {
        // check the info of urn and ilk
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        urn.ink = _add(urn.ink, dink);
        urn.art = _add(urn.art, dart);

        ilk.Art = _add(ilk.Art, dart);

        // calculate the actual debt 
        int dtab = _mul(ilk.rate, dart);

        // transfer the collateral from v to w 
        gem[i][v] = _sub(gem[i][v], dink);

        sin[w] = _sub(sin[w], dtab);
        vice = _sub(vice, dtab);
    }

    // --- Settlement ---
    function heal(uint rad) external {
        address u = msg.sender;
        sin[u] = _sub(sin[u], rad);
        dai[u] = _sub(dai[u], rad);
        vice = _sub(vice, rad);
        debt = _sub(debt, rad);
    }
    function suck(address u, address v, uint rad) external auth {
        sin[u] = _add(sin[u], rad);
        dai[v] = _add(dai[v], rad);
        vice = _add(vice, rad);
        debt = _add(debt, rad);
    }

    // --- Rates ---
    function fold(bytes32 i, address u, int rate) external auth {
        require(live == 1, "Vat/not-live");
        Ilk storage ilk = ilks[i];
        ilk.rate = _add(ilk.rate, rate);
        int rad = _mul(ilk.Art, rate);
        dai[u] = _add(dai[u], rad);
        debt = _add(debt, rad);
    }
}
