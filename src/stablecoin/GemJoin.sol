// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// use as interface for ERC20 token
interface IGem {
    function decimals() external view returns (uint8);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

// collateral depth position engine
interface ICDPEngine {
    function modify_collateral_balance(bytes32, address, int256) external;
}

contract Auth {
    event GrantAuthorization(address indexed usr);
    event DenyAuthorization(address indexed usr);

    // mapping for authorization
    mapping(address => bool) public authorized;
    // modifier to check if the sender is authorized

    modifier auth() {
        require(authorized[msg.sender], "unauthorized");
        _;
    }

    constructor() {
        authorized[msg.sender] = true;
        emit GrantAuthorization(msg.sender);
    }

    // function to authorize an address
    function grant_auth(address usr) external auth {
        authorized[usr] = true;
        emit GrantAuthorization(usr);
    }

    // function to deny authorization for an address
    function deny_auth(address usr) external auth {
        authorized[usr] = false;
        emit DenyAuthorization(usr);
    }
}

contract CircuitBreaker {
    event Stop();

    bool public live;

    constructor() {
        live = true;
    }

    modifier not_stopped() {
        require(live, "not stopped");
        _;
    }

    function _stop() internal {
        live = false;
        emit Stop();
    }
}

contract GemJoin is Auth, CircuitBreaker {
    ICDPEngine public cdp_engine; // CDP Engine
    bytes32 public collateral_type; // to identify the collateral type
    IGem public gem; // collateral to be locked inside the contract
    uint8 public decimals; // decimals of the collateral

    // Events

    event Join(address indexed usr, uint256 wad);
    event Exit(address indexed usr, uint256 wad);

    constructor(address _cdp_engine, bytes32 _collateral_type, address _gem) {
        cdp_engine = ICDPEngine(_cdp_engine);
        collateral_type = _collateral_type;
        gem = IGem(_gem);
        decimals = gem.decimals();
    }

    function stop() external auth {
        _stop();
    }

    // wad = 1e18
    // ray = 1e27
    // rad = 1e45
    // wad is amount of collateral to lock
    function join(address usr, uint256 wad) external not_stopped {
        require(int256(wad) >= 0, "overflow");
        // modify the collateral balance identified by collateral_type for usr
        cdp_engine.modify_collateral_balance(collateral_type, usr, int256(wad));
        // transfer collateral from user to this contract
        require(gem.transferFrom(msg.sender, address(this), wad), "transfer failed");
        emit Join(usr, wad);
    }
    // transfer collateral from this contract to user

    function exit(address usr, uint256 wad) external {
        require(wad <= 2 ** 255, "overflow");
        cdp_engine.modify_collateral_balance(collateral_type, msg.sender, -int256(wad));
        require(gem.transfer(usr, wad), "transfer failed");
        emit Exit(usr, wad);
    }
}
