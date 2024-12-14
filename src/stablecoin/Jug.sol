// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";

/// @title Jug - Stability Fee Collection
/// @notice Manages and collects stability fees for different collateral types
/// @dev Accumulates fees based on time elapsed and configured rates
contract Jug is Auth {
    /// @notice Fee configuration for a collateral type
    /// @dev Tracks per-second fee and last update time
    struct Collateral {
        // Per second stability fee [ray] - Collateral-specific
        uint256 fee;
        // Last fee collection timestamp [unix epoch time]
        uint256 updated_at;
    }

    /// @notice Fee parameters per collateral type
    mapping(bytes32 => Collateral) public collaterals;
    /// @notice CDP Engine for system interaction
    ICDPEngine public immutable cdp_engine;
    /// @notice Destination for collected fees
    address public ds_engine;
    /// @notice Global per-second stability fee [ray]
    uint256 public base_fee;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
    }

    /// @notice Initialize a new collateral type
    /// @param col_type Collateral identifier
    /// @dev Sets initial fee to RAY and current timestamp
    function init(bytes32 col_type) external auth {
        Collateral storage col = collaterals[col_type];
        require(col.fee == 0, "already initialized");
        col.fee = RAY;
        col.updated_at = block.timestamp;
    }

    /// @notice Update collateral-specific parameters
    /// @param col_type Collateral identifier
    /// @param key Parameter name
    /// @param val New parameter value
    /// @dev Only updates if last update was in current block
    function set(bytes32 col_type, bytes32 key, uint256 val) external auth {
        require(block.timestamp == collaterals[col_type].updated_at, "update time != now");
        if (key == "fee") {
            collaterals[col_type].fee = val;
        } else {
            revert("unrecognized param");
        }
    }
    /// @notice Update global fee parameters
    /// @param key Parameter name
    /// @param val New parameter value

    function set(bytes32 key, uint256 val) external auth {
        if (key == "base_fee") {
            base_fee = val;
        } else {
            revert("unrecognized param");
        }
    }
    /// @notice Set fee destination address
    /// @param key Parameter name
    /// @param val New address value

    function set(bytes32 key, address val) external auth {
        if (key == "ds_engine") {
            ds_engine = val;
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Collect accumulated stability fees
    /// @param col_type Collateral identifier
    /// @return rate Updated rate accumulator
    /// @dev Calculates and applies accumulated fees since last update
    function collect_stability_fee(bytes32 col_type) external returns (uint256 rate) {
        Collateral storage col = collaterals[col_type];
        require(col.updated_at <= block.timestamp, "now < last update");
        ICDPEngine.Collateral memory c = cdp_engine.collaterals(col_type);
        rate = Math.rmul(Math.rpow(base_fee + col.fee, block.timestamp - col.updated_at, RAY), c.rate_acc);
        cdp_engine.update_rate_acc(col_type, ds_engine, Math.diff(rate, c.rate_acc));
        col.updated_at = block.timestamp;
    }
}
