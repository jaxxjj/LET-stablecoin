// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

/// @title CDP Engine - Core CDP and System Debt Management
/// @notice Manages Collateralized Debt Positions (CDPs), system debt, and stability fees
/// @dev Core contract handling all CDP accounting and system state
contract CDPEngine is Auth, CircuitBreaker {
    /// @notice Configuration parameters for each collateral type
    /// @dev Includes debt ceiling, liquidation ratio, stability fee rate etc
    mapping(bytes32 => ICDPEngine.Collateral) public collaterals;

    /// @notice CDP positions for each user per collateral type
    /// @dev Tracks collateral locked and debt generated
    mapping(bytes32 => mapping(address => ICDPEngine.Position)) public positions;

    /// @notice Raw collateral balances per user and collateral type
    /// @dev Amount of tokens not yet locked in CDPs [wad]
    mapping(bytes32 => mapping(address => uint256)) public gem;

    /// @notice Stablecoin balances per address
    /// @dev Internal book-keeping of stablecoin amounts
    mapping(address => uint256) public coin;

    /// @notice Tracks debt balances that are not backed by collateral
    /// @dev Increases on grab/mint, decreases on burn [rad]
    mapping(address => uint256) public unbacked_debts;

    /// @notice Total system debt (all stablecoins issued) [rad]
    uint256 public sys_debt;

    /// @notice Total unbacked debt in the system [rad]
    uint256 public sys_unbacked_debt;

    /// @notice Global debt ceiling [rad]
    uint256 public sys_max_debt;

    /// @notice Authorization mapping for account management
    /// @dev Similar to ERC20 allowance - owner => operator => allowed
    mapping(address => mapping(address => bool)) public can;

    /// @notice Grant authorization to modify account
    /// @param user Address to authorize
    function allow_account_modification(address user) external {
        can[msg.sender][user] = true;
    }

    // deny authorization to user to modify account
    function deny_account_modification(address user) external {
        can[msg.sender][user] = false;
    }

    // check whether a person can modify the account: should be the owner or has been authorized
    function can_modify_account(address owner, address user) public view returns (bool) {
        return owner == user || can[owner][user];
    }

    // --- Administration ---
    // initialize the rate accumulation function and set its to 1
    function init(bytes32 col_type) external auth {
        require(collaterals[col_type].rate_acc == 0, "already initialized");
        collaterals[col_type].rate_acc = RAY;
    }

    // set the system parameters
    function set(bytes32 key, uint256 val) external auth not_stopped {
        if (key == "sys_max_debt") {
            sys_max_debt = val;
        } else {
            revert("unrecognized param");
        }
    }

    // set the collateral parameters
    function set(bytes32 col_type, bytes32 key, uint256 val) external auth not_stopped {
        if (key == "spot") {
            collaterals[col_type].spot = val;
        } else if (key == "max_debt") {
            collaterals[col_type].max_debt = val;
        } else if (key == "min_debt") {
            collaterals[col_type].min_debt = val;
        } else {
            revert("unrecognized param");
        }
    }

    // cage
    function stop() external auth {
        _stop();
    }

    // --- Fungibility ---
    // modify_collateral_balance - modify the collateral balance of a user.
    // positive wad means lock collateral
    // negative wad means free collateral
    // only called by GemJoin (only authorized)
    function modify_collateral_balance(bytes32 col_type, address src, int256 wad) external auth {
        // first reading the balance of the specific collateral type and the user balance, then adding the delta
        gem[col_type][src] = Math.add(gem[col_type][src], wad);
    }

    // flux - transfer collateral between users.
    function transfer_collateral(bytes32 col_type, address src, address dst, uint256 wad) external {
        require(can_modify_account(src, msg.sender), "not authorized");
        gem[col_type][src] -= wad;
        gem[col_type][dst] += wad;
    }

    // move - transfer stable coin between users.
    function transfer_coin(address src, address dst, uint256 rad) external {
        require(can_modify_account(src, msg.sender), "not authorized");
        coin[src] -= rad;
        coin[dst] += rad;
    }

    // --- CDP Manipulation ---
    // frob - modify a CDP
    // frob(i, u, v, w, dink, dart)
    // - modify position of user u
    // - using gem from user v
    // - and creating coin for user w
    // dink: change in amount of collateral
    // dart: change in amount of debt
    function modify_cdp(
        bytes32 col_type,
        address cdp,
        address gem_src,
        address coin_dst,
        // wad
        // delta_col >= 0 -> lock collateral
        //           <  0 -> free collateral
        int256 delta_col,
        // wad
        // delta_debt >= 0 -> borrow coin
        //            <  0 -> repay
        // delta_debt = borrow or repay coin amount * RAY / rate_acc
        int256 delta_debt
    ) external not_stopped {
        ICDPEngine.Position memory pos = positions[col_type][cdp];
        ICDPEngine.Collateral memory col = collaterals[col_type];
        require(col.rate_acc != 0, "collateral not initialized");

        pos.collateral = Math.add(pos.collateral, delta_col);
        // ci = coin amount at time i
        // ri = rate_acc at time i
        // c0 / r0 + c1 / r1 + c2 / r2 + ...
        pos.debt = Math.add(pos.debt, delta_debt);
        col.debt = Math.add(col.debt, delta_debt);

        // delta_debt = delta_coin / col.rate_acc
        // delta_coin [rad] = col.rate_acc * delta_debt
        int256 delta_coin = Math.mul(col.rate_acc, delta_debt);
        // coin balance + compound interest that the cdp owes to protocol
        // coin debt [rad]
        uint256 coin_debt = col.rate_acc * pos.debt;
        sys_debt = Math.add(sys_debt, delta_coin);

        // either debt has decreased, or debt ceilings are not exceeded
        require(
            delta_debt <= 0 || (col.debt * col.rate_acc <= col.max_debt && sys_debt <= sys_max_debt), "delta debt > max"
        );
        // cdp is either less risky than before, or it is safe
        require((delta_debt <= 0 && delta_col >= 0) || coin_debt <= pos.collateral * col.spot, "undercollateralized");
        // cdp is either more safe, or the owner consent
        require((delta_debt <= 0 && delta_col >= 0) || can_modify_account(cdp, msg.sender), "not allowed to modify cdp");
        // collateral src consent
        require(delta_col <= 0 || can_modify_account(gem_src, msg.sender), "not allowed to modify gem src");
        // coin dst consent
        require(delta_debt >= 0 || can_modify_account(coin_dst, msg.sender), "not allowed to modify coin dst");

        // cdp has no debt, or a non-dusty amount
        require(pos.debt == 0 || coin_debt >= col.min_debt, "debt < dust");

        // Moving col from gem to pos, hence opposite sign
        // lock collateral -> - gem, + pos
        // free collateral -> + gem, - pos
        gem[col_type][gem_src] = Math.sub(gem[col_type][gem_src], delta_col);
        coin[coin_dst] = Math.add(coin[coin_dst], delta_coin);

        positions[col_type][cdp] = pos;
        collaterals[col_type] = col;
    }

    // --- CDP Fungibility ---
    // fork - split a cdp - binary approval or splitting/merging positions.
    //    dink: amount of collateral to exchange.
    //    dart: amount of stable coin debt to exchange.
    function fork(bytes32 col_type, address cdp_src, address cdp_dst, int256 delta_col, int256 delta_debt) external {
        ICDPEngine.Position storage u = positions[col_type][cdp_src];
        ICDPEngine.Position storage v = positions[col_type][cdp_dst];
        ICDPEngine.Collateral storage col = collaterals[col_type];

        u.collateral = Math.sub(u.collateral, delta_col);
        u.debt = Math.sub(u.debt, delta_debt);
        v.collateral = Math.add(v.collateral, delta_col);
        v.debt = Math.add(v.debt, delta_debt);

        uint256 u_coin_debt = u.debt * col.rate_acc;
        uint256 v_coin_debt = v.debt * col.rate_acc;

        // both sides consent
        require(can_modify_account(cdp_src, msg.sender) && can_modify_account(cdp_dst, msg.sender), "not allowed");

        // both sides safe
        require(u_coin_debt <= u.collateral * col.spot, "not safe src");
        require(v_coin_debt <= v.collateral * col.spot, "not safe dst");

        // both sides non-dusty
        require(u_coin_debt >= col.min_debt || u.debt == 0, "dust src");
        require(v_coin_debt >= col.min_debt || v.debt == 0, "dust dst");
    }

    // --- CDP Confiscation ---
    // grab - liquidate a cdp
    // grab(i, u, v, w, dink, dart)
    // - modify the cdp of user u
    // - give gem to user v
    // - create sin for user w
    // liquidation process
    function grab(bytes32 col_type, address cdp, address gem_dst, address debt_dst, int256 delta_col, int256 delta_debt)
        external
        auth
    {
        ICDPEngine.Position storage pos = positions[col_type][cdp];
        ICDPEngine.Collateral storage col = collaterals[col_type];

        pos.collateral = Math.add(pos.collateral, delta_col);
        pos.debt = Math.add(pos.debt, delta_debt);
        col.debt = Math.add(col.debt, delta_debt);

        int256 delta_coin = Math.mul(col.rate_acc, delta_debt);

        gem[col_type][gem_dst] = Math.sub(gem[col_type][gem_dst], delta_col);
        unbacked_debts[debt_dst] = Math.sub(unbacked_debts[debt_dst], delta_coin);
        sys_unbacked_debt = Math.sub(sys_unbacked_debt, delta_coin);
    }

    // --- Settlement ---
    // heal - create / destroy equal quantities of stable coin and system debt (vice).
    function burn(uint256 rad) external {
        unbacked_debts[msg.sender] -= rad;
        coin[msg.sender] -= rad;
        sys_unbacked_debt -= rad;
        sys_debt -= rad;
    }

    // suck - mint unbacked stable coin (accounted for with vice).
    function mint(address debt_dst, address coin_dst, uint256 rad) external auth {
        unbacked_debts[debt_dst] += rad;
        coin[coin_dst] += rad;
        sys_unbacked_debt += rad;
        sys_debt += rad;
    }

    // --- Rates ---
    // modify the debt multiplier, creating / destroying corresponding debt.
    function update_rate_acc(bytes32 col_type, address coin_dst, int256 delta_rate_acc) external auth not_stopped {
        ICDPEngine.Collateral storage col = collaterals[col_type];
        // old total debt = col.debt * col.rate_acc
        // new total debt = col.debt * (col.rate_acc + delta_rate_acc)
        // delta coin = new total debt - old total debt
        col.rate_acc = Math.add(col.rate_acc, delta_rate_acc);
        int256 delta_coin = Math.mul(col.debt, delta_rate_acc);
        coin[coin_dst] = Math.add(coin[coin_dst], delta_coin);
        sys_debt = Math.add(sys_debt, delta_coin);
    }
}
