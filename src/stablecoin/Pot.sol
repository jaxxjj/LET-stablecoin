// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";
import "../lib/Math.sol";

/*
Pot is the core of the LET Savings Rate. 
It allows users to deposit LET and activate the LET Savings Rate and 
earning savings on their LET. The DSR is set by Maker Governance, and will 
typically be less than the base stability fee to remain sustainable. 
The purpose of Pot is to offer another incentive for holding LET.
*/
contract Pot is Auth, CircuitBreaker {
    // Normalised savings LET [wad]
    mapping(address => uint256) public pie;
    // Total normalised savings LET [wad]
    uint256 public total_pie;
    // LET savings rate [ray]
    uint256 public savings_rate;
    // Rate accumulator [ray]
    uint256 public rate_acc;

    ICDPEngine public cdp_engine;
    address public ds_engine;
    // Time of last collect_stability_fee [unix timestamp]
    uint256 public updated_at;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
        savings_rate = RAY;
        rate_acc = RAY;
        updated_at = block.timestamp;
    }

    /// @notice Update system parameters
    /// @param key Parameter name to update
    /// @param val New parameter value
    /// @dev Only callable by authorized addresses when system is not stopped
    function set(bytes32 key, uint256 val) external auth not_stopped {
        // check if the timestamp of last collect_stability_fee is the same as the current timestamp
        // cant update the savings rate if not call drip first
        require(block.timestamp == updated_at, "updated_at != now");
        if (key == "savings_rate") {
            savings_rate = val;
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Set system addresses
    /// @param key Address parameter name
    /// @param addr New address value
    /// @dev Only callable by authorized addresses
    function set(bytes32 key, address addr) external auth {
        // set the vow address
        if (key == "ds_engine") {
            ds_engine = addr;
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Emergency shutdown function
    /// @dev Sets savings rate to RAY and stops the contract
    function stop() external auth {
        _stop();
        savings_rate = RAY;
    }

    /// @notice Calculate and collect accumulated savings
    /// @return Current rate accumulator value
    /// @dev Updates rate accumulator and mints new LET for earned interest
    function collect_stability_fee() external returns (uint256) {
        require(block.timestamp >= updated_at, "now < updated_at");
        uint256 acc = Math.rmul(Math.rpow(savings_rate, block.timestamp - updated_at, RAY), rate_acc);
        uint256 delta_rate_acc = acc - rate_acc;
        rate_acc = acc;
        updated_at = block.timestamp;
        // prev total = rate_acc * total
        // new  total = new rate_acc * total
        // mint = new total - prev total = (new rate_acc - rate_acc) * total
        cdp_engine.mint(ds_engine, address(this), total_pie * delta_rate_acc);
        return acc;
    }

    /// @notice Deposit LET into savings
    /// @param wad Amount of LET to deposit [wad]
    /// @dev Requires rate accumulator to be up to date
    function join(uint256 wad) external {
        require(block.timestamp == updated_at, "updated_at != now");
        pie[msg.sender] += wad;
        total_pie += wad;
        cdp_engine.transfer_coin(msg.sender, address(this), rate_acc * wad);
    }

    /// @notice Withdraw LET from savings
    /// @param wad Amount of LET to withdraw [wad]
    /// @dev Transfers normalized amount * rate accumulator
    function exit(uint256 wad) external {
        pie[msg.sender] -= wad;
        total_pie -= wad;
        cdp_engine.transfer_coin(address(this), msg.sender, rate_acc * wad);
    }
}
