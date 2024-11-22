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
    // pie [wad] - Normalised savings LET
    mapping(address => uint256) public pie;
    // Pie [wad] - Total normalised savings LET
    uint256 public total_pie;
    // dsr [ray] - LET savings rate
    uint256 public savings_rate;
    // chi [ray] - Rate accumulator
    uint256 public rate_acc;

    // vat
    ICDPEngine public cdp_engine;
    // vow
    address public ds_engine;
    // rho [unix timestamp] - Time of last collect_stability_fee
    uint256 public updated_at;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
        savings_rate = RAY;
        rate_acc = RAY;
        updated_at = block.timestamp;
    }

    // --- Administration ---
    // file
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

    // file
    function set(bytes32 key, address addr) external auth {
        // set the vow address
        if (key == "ds_engine") {
            ds_engine = addr;
        } else {
            revert("unrecognized param");
        }
    }

    // cage
    function stop() external auth {
        _stop();
        savings_rate = RAY;
    }

    // --- Savings Rate Accumulation ---
    // drip
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

    // --- Savings LET Management ---

    //rate_acc must be up-to-date to the current timestamp
    // This ensures all previous interest has been properly accounted for
    // The conversion between pie and actual LET amounts will be accurate
    function join(uint256 wad) external {
        require(block.timestamp == updated_at, "updated_at != now");
        pie[msg.sender] += wad;
        total_pie += wad;
        cdp_engine.transfer_coin(msg.sender, address(this), rate_acc * wad);
    }

    function exit(uint256 wad) external {
        pie[msg.sender] -= wad;
        total_pie -= wad;
        cdp_engine.transfer_coin(address(this), msg.sender, rate_acc * wad);
    }
}
