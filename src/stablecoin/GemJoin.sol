// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IGem} from "../interfaces/IGem.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

/// @title GemJoin - Collateral Token Adapter
/// @notice Manages deposits and withdrawals of ERC20 tokens as collateral in the CDP system
/// @dev Acts as an adapter between external ERC20 tokens and the internal CDP accounting system
contract GemJoin is Auth, CircuitBreaker {
    /// @notice Emitted when collateral is deposited into the system
    /// @param user Address receiving the collateral position
    /// @param wad Amount of collateral tokens deposited [wad]
    event Join(address indexed user, uint256 wad);

    /// @notice Emitted when collateral is withdrawn from the system
    /// @param user Address receiving the withdrawn tokens
    /// @param wad Amount of collateral tokens withdrawn [wad]
    event Exit(address indexed user, uint256 wad);

    /// @notice CDP Engine contract for internal collateral accounting
    /// @dev Handles all CDP state updates and collateral tracking
    ICDPEngine public immutable cdp_engine;

    /// @notice Identifier for this collateral type in the CDP system
    /// @dev Used to differentiate between different collateral types
    bytes32 public immutable collateral_type;

    /// @notice ERC20 token contract used as collateral
    /// @dev Must be a valid ERC20 token with transfer and transferFrom
    IGem public immutable gem;

    /// @notice Decimal precision of the collateral token
    /// @dev Used for proper scaling of token amounts
    uint8 public immutable decimals;

    /// @notice Initializes the GemJoin adapter
    /// @param _cdp_engine Address of the CDP Engine contract
    /// @param _collateral_type Bytes32 identifier for this collateral type
    /// @param _gem Address of the ERC20 token to be used as collateral
    /// @dev Sets up the adapter with required contract references and collateral configuration
    constructor(address _cdp_engine, bytes32 _collateral_type, address _gem) {
        cdp_engine = ICDPEngine(_cdp_engine);
        collateral_type = _collateral_type;
        gem = IGem(_gem);
        decimals = gem.decimals();
    }

    /// @notice Emergency shutdown of the adapter
    /// @dev Can only be called by authorized addresses
    function stop() external auth {
        _stop();
    }

    /// @notice Deposit collateral tokens into the CDP system
    /// @param user Address to credit the collateral to
    /// @param wad Amount of tokens to deposit [wad]
    /// @dev Transfers tokens from msg.sender and updates CDP Engine balance
    function join(address user, uint256 wad) external not_stopped {
        require(int256(wad) >= 0, "overflow");
        cdp_engine.modify_collateral_balance(collateral_type, user, int256(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "transfer failed");
        emit Join(user, wad);
    }

    /// @notice Withdraw collateral tokens from the CDP system
    /// @param user Address to send withdrawn tokens to
    /// @param wad Amount of tokens to withdraw [wad]
    /// @dev Reduces CDP Engine balance and transfers tokens to user
    function exit(address user, uint256 wad) external {
        require(wad <= 2 ** 255, "overflow");
        cdp_engine.modify_collateral_balance(collateral_type, msg.sender, -int256(wad));
        require(gem.transfer(user, wad), "transfer failed");
        emit Exit(user, wad);
    }
}
