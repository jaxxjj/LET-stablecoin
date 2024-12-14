// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {ISurplusAuction} from "../interfaces/ISurplusAuction.sol";
import {IGem} from "../interfaces/IGem.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

/// @title Surplus Auction - Auction surplus LET for MKR
/// @notice This contract auctions excess LET (from stability fees) for MKR tokens
/// which are then burned, reducing MKR supply
/// @dev Uses an increasing price auction where bidders compete with higher MKR amounts
contract SurplusAuction is Auth, CircuitBreaker {
    /// @notice Emitted when a new auction starts
    /// @param id Unique identifier for the auction
    /// @param lot Amount of LET being auctioned [rad]
    /// @param bid Initial minimum bid in MKR [wad]
    event Start(uint256 id, uint256 lot, uint256 bid);

    /// @notice Stores auction state
    /// @dev Tracks current highest bid, LET amount, bidder, and timing
    mapping(uint256 => ISurplusAuction.Bid) public bids;

    /// @notice CDP Engine contract for LET transfers
    ICDPEngine public immutable cdp_engine;
    /// @notice MKR token contract that will be burned
    IGem public immutable gem;

    /// @notice Minimum bid increase ratio [wad]
    /// @dev 1.05e18 = 5% minimum increase
    uint256 public min_bid_increase = 1.05e18;

    /// @notice Maximum time a single bid can remain active [seconds]
    /// @dev After this time, auction can be restarted
    uint48 public bid_duration = 3 hours;

    /// @notice Maximum duration for entire auction [seconds]
    /// @dev After this time, auction must be restarted
    uint48 public auction_duration = 2 days;

    /// @notice Total number of auctions started
    uint256 public last_auction_id = 0;

    /// @notice Maximum amount of LET that can be in auction at once [rad]
    uint256 public max_coin_in_auction;

    /// @notice Current amount of LET in auction [rad]
    uint256 public total_coin_in_auction;

    /// @notice Creates a new SurplusAuction contract
    /// @param _cdp_engine Address of the CDP Engine
    /// @param _gem Address of the MKR token
    constructor(address _cdp_engine, address _gem) {
        cdp_engine = ICDPEngine(_cdp_engine);
        gem = IGem(_gem);
    }

    /// @notice Configure auction parameters
    /// @param key Parameter name to set
    /// @param val New value for parameter
    /// @dev Only callable by authorized addresses
    function set(bytes32 key, uint256 val) external auth {
        if (key == keccak256(abi.encodePacked("min_bid_increase"))) {
            min_bid_increase = val;
        } else if (key == keccak256(abi.encodePacked("bid_duration"))) {
            bid_duration = uint48(val);
        } else if (key == keccak256(abi.encodePacked("auction_duration"))) {
            auction_duration = uint48(val);
        } else if (key == keccak256(abi.encodePacked("max_coin_in_auction"))) {
            max_coin_in_auction = val;
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Start a new surplus auction
    /// @param lot Amount of LET to auction [rad]
    /// @param bid_amount Initial minimum bid in MKR [wad]
    /// @return id Unique identifier for the new auction
    /// @dev Only callable by authorized addresses when system is not stopped
    function start(uint256 lot, uint256 bid_amount) external auth not_stopped returns (uint256 id) {
        total_coin_in_auction += lot;
        require(total_coin_in_auction <= max_coin_in_auction, "total > max");
        id = ++last_auction_id;

        bids[id] = ISurplusAuction.Bid({
            amount: bid_amount,
            lot: lot,
            highest_bidder: msg.sender,
            bid_expiry_time: 0,
            auction_end_time: uint48(block.timestamp) + auction_duration
        });

        cdp_engine.transfer_coin(msg.sender, address(this), lot);
        emit Start(id, lot, bid_amount);
    }

    /// @notice Restart an expired auction
    /// @param id Auction identifier to restart
    /// @dev Resets auction timer if no bids placed and auction expired
    function restart(uint256 id) external {
        ISurplusAuction.Bid storage b = bids[id];
        require(b.auction_end_time < block.timestamp, "not finished");
        require(b.bid_expiry_time == 0, "bid already placed");
        b.auction_end_time = uint48(block.timestamp) + auction_duration;
    }

    /// @notice Submit a new bid for an auction
    /// @param id Auction identifier
    /// @param lot Amount of LET being bid on [rad]
    /// @param bid_amount New bid amount in MKR [wad]
    /// @dev Must increase bid by minimum percentage, transfers MKR from bidder
    function bid(uint256 id, uint256 lot, uint256 bid_amount) external not_stopped {
        ISurplusAuction.Bid storage b = bids[id];
        require(b.highest_bidder != address(0), "bidder not set");
        require(block.timestamp < b.bid_expiry_time || b.bid_expiry_time == 0, "bid expired");
        require(block.timestamp < b.auction_end_time, "auction ended");

        require(lot == b.lot, "lot not matching");
        require(bid_amount > b.amount, "bid <= current");
        require(bid_amount * WAD >= min_bid_increase * b.amount, "insufficient increase");

        if (msg.sender != b.highest_bidder) {
            gem.move(msg.sender, b.highest_bidder, b.amount);
            b.highest_bidder = msg.sender;
        }
        gem.move(msg.sender, address(this), bid_amount - b.amount);

        b.amount = bid_amount;
        b.bid_expiry_time = uint48(block.timestamp) + auction_duration;
    }

    /// @notice Claim auction proceeds after completion
    /// @param id Auction identifier to settle
    /// @dev Transfers LET to winner, burns MKR, only when auction completed
    function claim(uint256 id) external not_stopped {
        ISurplusAuction.Bid storage b = bids[id];
        require(
            b.bid_expiry_time != 0 && (b.bid_expiry_time < block.timestamp || b.auction_end_time < block.timestamp),
            "not finished"
        );
        cdp_engine.transfer_coin(address(this), b.highest_bidder, b.lot);
        gem.burn(address(this), b.amount);
        delete bids[id];
        total_coin_in_auction -= b.lot;
    }

    /// @notice Emergency stop function
    /// @param rad Amount of LET to recover [rad]
    /// @dev Only callable by authorized addresses
    function stop(uint256 rad) external auth {
        _stop();
        cdp_engine.transfer_coin(address(this), msg.sender, rad);
    }

    /// @notice Cancel an auction and return funds
    /// @param id Auction identifier to cancel
    /// @dev Returns MKR to highest bidder, only when system not stopped
    function yank(uint256 id) external not_stopped {
        ISurplusAuction.Bid storage b = bids[id];
        require(b.highest_bidder != address(0), "bidder not set");
        gem.move(address(this), b.highest_bidder, b.amount);
        delete bids[id];
    }
}
