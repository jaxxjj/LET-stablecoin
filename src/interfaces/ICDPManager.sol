// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface ICDPManager {
    struct List {
        uint256 prev;
        uint256 next;
    }

    function cdp_engine() external view returns (address);

    function last_cdp_id() external view returns (uint256);

    function positions(uint256 cdp_id) external view returns (address);

    function list(uint256 cdp_id) external view returns (List memory);

    function owner_of(uint256 cdp_id) external view returns (address);

    function collaterals(uint256 cdp_id) external view returns (bytes32);

    function first(address owner) external view returns (uint256);

    function last(address owner) external view returns (uint256);

    function count(address owner) external view returns (uint256);

    // permission to modify cdp by addr
    function cdp_can(address owner, uint256 cdp_id, address user) external view returns (bool);

    function cdp_handler_can(address owner, address user) external view returns (bool);

    function allow_cdp(uint256 cdp_id, address user, bool ok) external;

    function allow_cdp_handler(address user, bool ok) external;

    function open(bytes32 col_type, address user) external returns (uint256 id);

    function give(uint256 cdp_id, address dst) external;

    function modify_cdp(uint256 cdp_id, int256 delta_col, int256 delta_debt) external;

    function transfer_collateral(uint256 cdp_id, address dst, uint256 wad) external;

    function transfer_collateral(bytes32 col_type, uint256 cdp_id, address dst, uint256 wad) external;

    function transfer_coin(uint256 cdp_id, address dst, uint256 rad) external;

    function quit(uint256 cdp_id, address cdp_dst) external;

    function enter(address cdp_src, uint256 cdp_id) external;

    function shift(uint256 cdp_src, uint256 cdp_dst) external;
}
