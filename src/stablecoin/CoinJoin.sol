// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// CoinJoin - used to join and exit stablecoin
contract CoinJoin is Auth, CircuitBreaker {
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);

    ICDPEngine public immutable cdp_engine;
    ICoin public immutable coin;

    constructor(address _cdp_engine, address _coin) {
        cdp_engine = ICDPEngine(_cdp_engine);
        coin = ICoin(_coin);
    }

    function stop() external auth {
        _stop();
    }

    function join(address user, uint256 wad) external {
        // internal record of the amount of stablecoin
        cdp_engine.transfer_coin(address(this), user, wad * RAY);
        // burn LET stablecoin
        coin.burn(msg.sender, wad);
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external not_stopped {
        cdp_engine.transfer_coin(msg.sender, address(this), wad * RAY);
        // mint LET stablecoin
        coin.mint(user, wad);
        emit Exit(user, wad);
    }
}
