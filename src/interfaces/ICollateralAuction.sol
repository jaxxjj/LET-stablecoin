// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface ICollateralAuction {
    struct Sale {
        //  Index in active array
        uint256 pos;
        //  Amount of coin to raise
        uint256 coin_amount;
        //  Amount of collateral to sell
        uint256 collateral_amount;
        //  Liquidated CDP
        address user;
        //  Auction start time
        uint96 start_time;
        //  Starting price
        uint256 starting_price;
    }

    function stop() external;
    function sales(uint256 sale_id) external view returns (Sale memory);
    function collateral_type() external view returns (bytes32);
    function start(uint256 coin_amount, uint256 collateral_amount, address user, address keeper)
        external
        returns (uint256);
}
