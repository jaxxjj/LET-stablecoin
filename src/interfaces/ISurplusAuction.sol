// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface ISurplusAuction {
    struct Bid {
        // MKR paid
        uint256 amount;
        // BEI in return for bid (rad)
        uint256 lot;
        // high bidder
        address highest_bidder;
        // bid expiry time
        uint48 bid_expiry_time;
        // auction expiry time
        uint48 auction_end_time;
    }

    function bids(uint256 id) external view returns (Bid memory);
    function start(uint256 lot, uint256 bid_amount) external returns (uint256);
    function stop(uint256) external;
}
