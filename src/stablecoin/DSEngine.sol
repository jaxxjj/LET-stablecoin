// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IDebtAuction} from "../interfaces/IDebtAuction.sol";
import {ISurplusAuction} from "../interfaces/ISurplusAuction.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

/// @title DSEngine - Debt and Surplus Management Engine
/// @notice Manages system debt from liquidations and surplus from stability fees
/// @dev Core accounting contract that maintains system solvency through auctions
contract DSEngine is Auth, CircuitBreaker {
    /// @notice CDP Engine interface for system state
    ICDPEngine public immutable cdp_engine;
    /// @notice Surplus auction contract for selling excess LET
    ISurplusAuction public surplus_auction;
    /// @notice Debt auction contract for covering bad debt
    IDebtAuction public debt_auction;

    /// @notice Mapping of timestamp to queued debt amount [rad]
    mapping(uint256 => uint256) public debt_queue;
    /// @notice Total debt currently in queue [rad]
    uint256 public total_debt_on_queue;
    /// @notice Total debt currently in debt auctions [rad]
    uint256 public total_debt_on_debt_auction;

    /// @notice Delay before debt can be popped from queue [seconds]
    uint256 public pop_debt_delay;
    /// @notice Amount of protocol tokens (MKR) to mint in debt auction [wad]
    uint256 public debt_auction_lot_size;
    /// @notice Amount of debt to auction in debt auction [rad]
    uint256 public debt_auction_bid_size;
    /// @notice Amount of surplus LET to auction in surplus auction [rad]
    uint256 public surplus_auction_lot_size;
    /// @notice Minimum surplus required to trigger surplus auction [rad]
    uint256 public min_surplus;

    constructor(address _cdp_engine, address _surplus_auction, address _debt_auction) {
        cdp_engine = ICDPEngine(_cdp_engine);
        surplus_auction = ISurplusAuction(_surplus_auction);
        debt_auction = IDebtAuction(_debt_auction);
        cdp_engine.allow_account_modification(_surplus_auction);
    }

    // --- Administration ---
    function set(bytes32 key, uint256 val) external auth {
        if (key == keccak256(abi.encode("pop_debt_delay"))) {
            pop_debt_delay = val;
        } else if (key == keccak256(abi.encode("surplus_auction_lot_size"))) {
            surplus_auction_lot_size = val;
        } else if (key == keccak256(abi.encode("debt_auction_bid_size"))) {
            debt_auction_bid_size = val;
        } else if (key == keccak256(abi.encode("debt_auction_lot_size"))) {
            debt_auction_lot_size = val;
        } else if (key == keccak256(abi.encode("min_surplus"))) {
            min_surplus = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 key, address val) external auth {
        if (key == keccak256(abi.encode("surplus_auction"))) {
            cdp_engine.deny_account_modification(address(surplus_auction));
            surplus_auction = ISurplusAuction(val);
            cdp_engine.allow_account_modification(val);
        } else if (key == keccak256(abi.encode("debt_auction"))) {
            debt_auction = IDebtAuction(val);
        } else {
            revert("unrecognized param");
        }
    }

    /// @notice Push debt from liquidation into queue
    /// @param debt Amount of debt to queue [rad]
    function push_debt_to_queue(uint256 debt) external auth {
        debt_queue[block.timestamp] += debt;
        total_debt_on_queue += debt;
    }

    /// @notice Pop debt from queue after delay
    /// @param t Timestamp of debt to pop
    function pop_debt_from_queue(uint256 t) external {
        require(t + pop_debt_delay <= block.timestamp, "delay not finished");
        total_debt_on_queue -= debt_queue[t];
        debt_queue[t] = 0;
    }

    /// @notice Settle system debt with available surplus
    /// @param rad Amount of debt to settle [rad]
    function settle_debt(uint256 rad) external {
        require(rad <= cdp_engine.coin(address(this)), "insufficient coin");
        // rad + total debt on queue + auction <= unbacked debt
        require(
            rad <= cdp_engine.unbacked_debts(address(this)) - total_debt_on_queue - total_debt_on_debt_auction,
            "insufficient debt"
        );
        cdp_engine.burn(rad);
    }

    /// @notice Start auction to sell surplus LET for MKR
    /// @return id Auction ID
    function start_surplus_auction() external returns (uint256 id) {
        require(
            cdp_engine.coin(address(this))
                >= cdp_engine.unbacked_debts(address(this)) + surplus_auction_lot_size + min_surplus,
            "insufficient coin"
        );
        // unbacked debt = total debt on queue + total debt on auction
        // All unbacked debt must currently be in auctions
        require(
            cdp_engine.unbacked_debts(address(this)) == total_debt_on_queue + total_debt_on_debt_auction,
            "debt not zero"
        );
        id = surplus_auction.start(surplus_auction_lot_size, 0);
    }

    /// @notice Start auction to sell MKR for LET to cover bad debt
    /// @return id Auction ID
    function start_debt_auction() external returns (uint256 id) {
        // bid size + total debt on queue + auction <= unbacked debts
        // Unbacked debt must be >= debt in auctions + debt to be auctioned
        require(
            debt_auction_bid_size + total_debt_on_queue + total_debt_on_debt_auction
                <= cdp_engine.unbacked_debts(address(this)),
            "insufficient debt"
        );
        require(cdp_engine.coin(address(this)) == 0, "coin not zero");
        total_debt_on_debt_auction += debt_auction_bid_size;
        id = debt_auction.start({
            highest_bidder: address(this),
            lot: debt_auction_lot_size,
            bid_amount: debt_auction_bid_size
        });
    }

    function stop() external auth {
        _stop();
        total_debt_on_queue = 0;
        total_debt_on_debt_auction = 0;
        surplus_auction.stop(cdp_engine.coin(address(surplus_auction)));
        debt_auction.stop();
        cdp_engine.burn(Math.min(cdp_engine.coin(address(this)), cdp_engine.unbacked_debts(address(this))));
    }
}
