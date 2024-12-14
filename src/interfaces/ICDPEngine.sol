// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface ICDPEngine {
    // a collateral type
    struct Collateral {
        // total normalized stablecoin debt [wad]
        uint256 debt;
        // stablecoin debt multiplier (accumulated stability fees) [ray]
        uint256 rate_acc;
        // liquidation price [ray]
        uint256 spot;
        // debt ceiling for a specific collateral type [rad]
        uint256 max_debt;
        // debt floor for a specific collateral type [rad]
        uint256 min_debt;
    }

    //a specific vault (CDP)
    struct Position {
        // collateral balance [wad]
        uint256 collateral;
        // normalized outstanding stablecoin debt [wad]
        uint256 debt;
    }

    // --- Auth ---
    function authorized(address user) external view returns (bool);

    function grant_auth(address user) external;

    function deny_auth(address user) external;

    function can(address owner, address user) external view returns (bool);

    function allow_account_modification(address user) external;

    function deny_account_modification(address user) external;

    function can_modify_account(address owner, address user) external view returns (bool);

    // --- Data ---

    function collaterals(bytes32 col_type) external view returns (Collateral memory);

    function positions(bytes32 col_type, address account) external view returns (Position memory);
    // [wad]
    function gem(bytes32 col_type, address account) external view returns (uint256);
    // LET [rad]
    function coin(address account) external view returns (uint256);
    // [rad]
    function unbacked_debts(address account) external view returns (uint256);
    // [rad]
    function sys_debt() external view returns (uint256);
    //[rad]
    function sys_unbacked_debt() external view returns (uint256);
    // [rad]
    function sys_max_debt() external view returns (uint256);

    // --- Administration ---
    function init(bytes32 col_type) external;
    function set(bytes32 key, uint256 val) external;
    function set(bytes32 col_type, bytes32 key, uint256 val) external;
    function stop() external;

    // --- Fungibility ---

    function modify_collateral_balance(bytes32 col_type, address src, int256 wad) external;

    function transfer_collateral(bytes32 col_type, address src, address dst, uint256 wad) external;

    function transfer_coin(address src, address dst, uint256 rad) external;

    // --- CDP Manipulation ---

    function modify_cdp(
        bytes32 col_type,
        address cdp,
        address gem_src,
        address coin_dst,
        // [wad]
        int256 delta_col,
        // [wad]
        int256 delta_debt
    ) external;

    // --- CDP Fungibility ---
    function fork(
        bytes32 col_type,
        address cdp_src,
        address cdp_dst,
        // [wad]
        int256 delta_col,
        // [wad]
        int256 delta_debt
    ) external;
    function grab(
        bytes32 col_type,
        address cdp,
        address gem_dst,
        address debt_dst,
        // [wad]
        int256 delta_col,
        // [wad]
        int256 delta_debt
    ) external;

    // --- Settlement ---
    function burn(uint256 rad) external;
    function mint(address debt_dst, address coin_dst, uint256 rad) external;

    // --- Rates ---
    function update_rate_acc(bytes32 col_type, address coin_dst, int256 delta_rate_acc) external;
}
