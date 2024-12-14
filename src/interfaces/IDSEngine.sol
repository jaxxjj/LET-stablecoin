// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface IDSEngine {
    function cdp_engine() external view returns (address);
    function surplus_auction() external view returns (address);
    function debt_auction() external view returns (address);
    function debt_queue(uint256 timestamp) external view returns (uint256);
    function total_debt_on_queue() external view returns (uint256);
    function total_debt_on_debt_auction() external view returns (uint256);
    function pop_debt_delay() external view returns (uint256);
    function debt_auction_lot_size() external view returns (uint256);
    function debt_auction_bid_size() external view returns (uint256);
    function surplus_auction_lot_size() external view returns (uint256);
    function surplus_buffer() external view returns (uint256);
    function push_debt_to_queue(uint256 debt) external;
    function pop_debt_from_queue(uint256 timestamp) external;
    function settle_debt(uint256 rad) external;
    function decrease_auction_debt(uint256 rad) external;
    function start_debt_auction() external returns (uint256 id);
    function start_surplus_auction() external returns (uint256 id);
    function stop() external;
}
