// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ICollateralAuction} from "../interfaces/ICollateralAuction.sol";
import {ISpotter} from "../interfaces/ISpotter.sol";

contract EmergencyShutdown is Auth {
    // --- Events ---
    event ShutdownSystem();
    event SetFinalPrice(bytes32 indexed col_type, uint256 final_price);

    // --- State Variables ---
    bool public shutdown;
    uint256 public shutdown_time;
    mapping(bytes32 => uint256) public final_prices;

    ICDPEngine public immutable cdp_engine;
    IOracle public immutable oracle;
    ICollateralAuction public immutable collateral_auction;
    ISpotter public immutable spotter;

    constructor(address _cdp_engine, address _oracle, address _collateral_auction, address _spotter) {
        cdp_engine = ICDPEngine(_cdp_engine);
        oracle = IOracle(_oracle);
        collateral_auction = ICollateralAuction(_collateral_auction);
        spotter = ISpotter(_spotter);
    }

    // --- Core Functions ---
    function shutdown_system() external auth {
        require(!shutdown, "system already shutdown");
        shutdown = true;
        shutdown_time = block.timestamp;

        // Stop price feeds
        oracle.stop();

        // Stop auctions
        collateral_auction.stop();

        // Stop CDP operations
        cdp_engine.stop();

        // Stop price updates
        spotter.stop();

        emit ShutdownSystem();
    }

    function set_final_price(bytes32 col_type) external auth {
        require(shutdown, "system not shutdown");
        require(final_prices[col_type] == 0, "final price already set");

        (bytes32 price, bool valid) = oracle.peek();
        require(valid, "invalid price");

        final_prices[col_type] = uint256(price);

        emit SetFinalPrice(col_type, uint256(price));
    }

    // Users can redeem their collateral at the final price
    function redeem_collateral(bytes32 col_type, uint256 amount) external {
        require(shutdown, "system not shutdown");
        require(final_prices[col_type] != 0, "final price not set");

        // Calculate coin amount based on final price
        uint256 coin_amount = Math.rmul(amount, final_prices[col_type]);

        // Transfer collateral to user
        cdp_engine.transfer_collateral(col_type, address(this), msg.sender, amount);

        // Burn user's stablecoin
        cdp_engine.transfer_coin(msg.sender, address(this), coin_amount);
    }
}
