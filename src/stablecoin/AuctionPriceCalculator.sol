// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {Auth} from "../lib/Auth.sol";
import "../lib/Math.sol";

/// @title Linear Price Calculator for Dutch Auctions
/// @notice Implements linear price decrease over time for collateral auctions
/// @dev Price decreases linearly from initial price to zero over duration
contract LinearDecrease is Auth {
    /// @notice Duration until price reaches zero [seconds]
    /// @dev After this time, auction needs restart
    uint256 public duration;

    /// @notice Configure calculator parameters
    /// @param key Parameter name to set
    /// @param val New value for parameter
    /// @dev Only callable by authorized addresses
    function set(bytes32 key, uint256 val) external auth {
        if (key == "duration") {
            duration = val;
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Calculate current auction price
    /// @param top Initial auction price [ray]
    /// @param dt Time elapsed since auction start [seconds]
    /// @return Current auction price [ray]
    /// @dev Price = initial_price * (duration - elapsed_time)/duration
    function price(uint256 top, uint256 dt) external view returns (uint256) {
        if (duration <= dt) {
            return 0;
        }
        return Math.rmul(top, (duration - dt) * RAY / duration);
    }
}

/// @title Stairstep Exponential Price Calculator
/// @notice Implements stepwise exponential price decrease for collateral auctions
/// @dev Price drops by fixed percentage at regular time intervals
contract StairstepExponentialDecrease is Auth {
    /// @notice Time between price drops [seconds]
    uint256 public step;
    /// @notice Price reduction per step [ray]
    /// @dev 0.95e27 = 5% reduction
    uint256 public cut;

    /// @notice Configure calculator parameters
    /// @param key Parameter name to set
    /// @param val New value for parameter
    /// @dev Only callable by authorized addresses
    function set(bytes32 key, uint256 val) external auth {
        if (key == "cut") {
            require((cut = val) <= RAY, "StairstepExponentialDecrease/cut-gt-RAY");
        } else if (key == "step") {
            step = val;
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Calculate current auction price
    /// @param top Initial auction price [ray]
    /// @param dt Time elapsed since auction start [seconds]
    /// @return Current auction price [ray]
    /// @dev Price = initial_price * (cut ^ (elapsed_time/step))
    function price(uint256 top, uint256 dt) external view returns (uint256) {
        return Math.rmul(top, Math.rpow(cut, dt / step, RAY));
    }
}

/// @title Continuous Exponential Price Calculator
/// @notice Implements smooth exponential price decrease for collateral auctions
/// @dev Price decreases continuously using exponential decay function
contract ExponentialDecrease is Auth {
    /// @notice Exponential decay rate [ray]
    uint256 public decay;
    /// @notice Maximum auction duration [seconds]
    uint256 public duration;

    /// @notice Configure calculator parameters
    /// @param key Parameter name to set
    /// @param val New value for parameter
    /// @dev Only callable by authorized addresses
    function set(bytes32 key, uint256 val) external auth {
        if (key == "decay") {
            require(val <= RAY, "ExponentialDecrease/decay-gt-RAY");
            decay = val;
        } else if (key == "duration") {
            duration = val;
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Calculate current auction price
    /// @param top Initial auction price [ray]
    /// @param dt Time elapsed since auction start [seconds]
    /// @return Current auction price [ray]
    /// @dev Price = initial_price * e^(-decay * elapsed_time)
    function price(uint256 top, uint256 dt) external view returns (uint256) {
        if (duration <= dt) {
            return 0;
        }

        // Calculate e^(-decay * t) using rpow
        uint256 power = Math.rpow(RAY - decay, dt, RAY);

        // Multiply by initial price
        return Math.rmul(top, power);
    }
}
