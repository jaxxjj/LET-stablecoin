// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IDSEngine} from "../interfaces/IDSEngine.sol";
import {ICollateralAuction} from "../interfaces/ICollateralAuction.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// Dog
contract LiquidationEngine is Auth, CircuitBreaker {
    event Liquidate(
        bytes32 indexed col_type,
        address indexed cdp,
        uint256 delta_col,
        uint256 delta_debt,
        uint256 due,
        address auction,
        uint256 indexed id
    );
    event Remove(bytes32 col_type, uint256 rad);

    // Ilk
    struct Collateral {
        // clip - Address of collateral auction
        address auction;
        // chop [wad] - Liquidation penalty multiplier
        uint256 penalty;
        // hole [rad] - Max LET needed to cover debt+fees of active auctions per collateral
        uint256 max_coin;
        // dirt [rad] - Amountt of LET needed to cover debt+fees of active auctions per collateral
        uint256 coin_amount;
    }

    // vat
    ICDPEngine public immutable cdp_engine;
    // ilks
    mapping(bytes32 => Collateral) public collaterals;
    // vow
    IDSEngine public ds_engine;
    // Hole [rad] - Max LET needed to cover debt + fees of active auctions
    uint256 public max_coin;
    // Dirt [rad] - Amount LET needed to cover debt + fees of active auctions
    uint256 public total_coin;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
    }

    // --- Administration ---
    // file
    function set(bytes32 key, address addr) external auth {
        if (key == "ds_engine") {
            ds_engine = IDSEngine(addr);
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 key, uint256 val) external auth {
        if (key == "max_coin") {
            max_coin = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 col_type, bytes32 key, uint256 val) external auth {
        if (key == "penalty") {
            require(val >= WAD, "penalty < WAD");
            collaterals[col_type].penalty = val;
        } else if (key == "max_coin") {
            collaterals[col_type].max_coin = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 col_type, bytes32 key, address auction) external auth {
        if (key == "auction") {
            require(col_type == ICollateralAuction(auction).collateral_type(), "col type != auction col type");
            collaterals[col_type].auction = auction;
        } else {
            revert("unrecognized param");
        }
    }

    // chop
    function penalty(bytes32 col_type) external view returns (uint256) {
        return collaterals[col_type].penalty;
    }

    // bark
    function liquidate(bytes32 col_type, address cdp, address keeper) external not_stopped returns (uint256 id) {
        ICDPEngine.Position memory pos = cdp_engine.positions(col_type, cdp);
        ICDPEngine.Collateral memory c = cdp_engine.collaterals(col_type);
        Collateral memory col = collaterals[col_type];
        uint256 delta_debt;
        {
            // check initialized
            require(c.spot > 0 && pos.collateral * c.spot < pos.debt * c.rate_acc, "not unsafe");

            // check if the liquidation limit is reached
            require(max_coin > total_coin && col.max_coin > col.coin_amount, "liquidation limit");
            // room [rad]
            // max amount of LET that can be liquidated
            uint256 room = Math.min(max_coin - total_coin, col.max_coin - col.coin_amount);

            // target coin for auction = debt * rate acc * penalty
            delta_debt = Math.min(pos.debt, room * WAD / c.rate_acc / col.penalty);

            // Partial liquidation edge case logic
            if (pos.debt > delta_debt) {
                if ((pos.debt - delta_debt) * c.rate_acc < c.min_debt) {
                    // If the leftovers would be dusty, just liquidate it entirely.
                    // This will result in at least one of dirt_i > hole_i or Dirt > Hole becoming true.
                    // The amount of excess will be bounded above by ceiling(dust_i * chop_i / WAD).
                    // This deviation is assumed to be small compared to both hole_i and Hole, so that
                    // the extra amount of target LET over the limits intended is not of economic concern.
                    delta_debt = pos.debt;
                } else {
                    // In a partial liquidation, the resulting auction should also be non-dusty.
                    require(delta_debt * c.rate_acc >= c.min_debt, "dusty auction from partial liquidation");
                }
            }
        }

        uint256 delta_col = (pos.collateral * delta_debt) / pos.debt;

        require(delta_col > 0, "null auction");
        require(delta_debt <= 2 ** 255 && delta_col <= 2 ** 255, "overflow");

        // collateral sent to aution, debt sent to debt/surplus engine
        cdp_engine.grab({
            col_type: col_type,
            cdp: cdp,
            gem_dst: col.auction,
            debt_dst: address(ds_engine),
            delta_col: -int256(delta_col),
            delta_debt: -int256(delta_debt)
        });

        uint256 due = delta_debt * c.rate_acc;
        ds_engine.push_debt_to_queue(due);

        {
            // Avoid stack too deep
            // This calcuation will overflow if delta_debt*rate_acc exceeds ~10^14
            // target coin amount = delta debt * rate acc * penalty / WAD
            //         delta debt = min(pos.debt, room * WAD / rate acc / penalty)
            //          delta col = pos.collateral * delta debt / pos.debt
            uint256 target_coin_amount = due * col.penalty / WAD;
            total_coin += target_coin_amount;
            collaterals[col_type].coin_amount += target_coin_amount;

            id = ICollateralAuction(col.auction).start({
                // tab - the target LET to raise from the auction (debt + stability fees + liquidation penalty) [rad]
                coin_amount: target_coin_amount,
                // lot - the amount of collateral available for purchase [wad]
                collateral_amount: delta_col,
                user: cdp,
                keeper: keeper
            });
        }

        emit Liquidate(col_type, cdp, delta_col, delta_debt, due, col.auction, id);
    }

    // digs
    function remove_coin_from_auction(bytes32 col_type, uint256 rad) external auth {
        total_coin -= rad;
        collaterals[col_type].coin_amount -= rad;
        emit Remove(col_type, rad);
    }

    // cage
    function stop() external auth {
        _stop();
    }
}
