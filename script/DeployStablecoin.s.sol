// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/stablecoin/CDPEngine.sol";
import "../src/stablecoin/Jug.sol";
import "../src/stablecoin/DSEngine.sol";
import "../src/cdp-manager/CDPManager.sol";
import "../src/stablecoin/GemJoin.sol";
import "../src/stablecoin/CoinJoin.sol";
import "../src/stablecoin/Spotter.sol";
import "../src/stablecoin/SurplusAuction.sol";
import "../src/stablecoin/DebtAuction.sol";
import "../src/stablecoin/Coin.sol";

contract DeployStablecoin is Script {
    // System contracts
    CDPEngine public cdp_engine;
    Jug public jug;
    DSEngine public ds_engine;
    CDPManager public cdp_manager;
    GemJoin public gem_join;
    CoinJoin public coin_join;
    Spotter public spotter;
    SurplusAuction public surplus_auction;
    DebtAuction public debt_auction;

    // Tokens
    Coin public coin; // Stablecoin
    address constant GOV_TOKEN = 0xF9aFd1f757641d7e1a652A18db4526C696D01ef9;
    // Goerli WETH address - change for other networks
    address constant WETH = 0x33322659739034C907FC25102d79eF4b4F285ff4;

    // Configuration constants
    bytes32 constant ETH_A = "ETH-A";
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy stablecoin
        coin = new Coin();
        console.log("Stablecoin deployed at:", address(coin));

        // Deploy core contracts
        cdp_engine = new CDPEngine();
        console.log("CDPEngine deployed at:", address(cdp_engine));

        // Deploy auction contracts with existing gov token
        surplus_auction = new SurplusAuction(address(cdp_engine), GOV_TOKEN);
        console.log("SurplusAuction deployed at:", address(surplus_auction));

        debt_auction = new DebtAuction(address(cdp_engine), GOV_TOKEN);
        console.log("DebtAuction deployed at:", address(debt_auction));

        // Deploy DSEngine with auction contracts
        ds_engine = new DSEngine(address(cdp_engine), address(surplus_auction), address(debt_auction));
        console.log("DSEngine deployed at:", address(ds_engine));

        jug = new Jug(address(cdp_engine));
        console.log("Jug deployed at:", address(jug));

        cdp_manager = new CDPManager(address(cdp_engine));
        console.log("CDPManager deployed at:", address(cdp_manager));

        // Deploy peripheral contracts with actual WETH address
        gem_join = new GemJoin(address(cdp_engine), ETH_A, WETH);
        console.log("GemJoin deployed at:", address(gem_join));

        coin_join = new CoinJoin(address(cdp_engine), address(coin));
        console.log("CoinJoin deployed at:", address(coin_join));

        spotter = new Spotter(address(cdp_engine));
        console.log("Spotter deployed at:", address(spotter));

        // Initialize system
        initializeSystem();

        vm.stopBroadcast();
    }

    function initializeSystem() internal {
        // Previous initialization code remains the same
        // Grant permissions
        cdp_engine.grant_auth(address(jug));
        cdp_engine.grant_auth(address(ds_engine));
        cdp_engine.grant_auth(address(cdp_manager));
        cdp_engine.grant_auth(address(gem_join));
        cdp_engine.grant_auth(address(coin_join));
        cdp_engine.grant_auth(address(spotter));

        // Initialize ETH-A in CDPEngine
        cdp_engine.init(ETH_A);

        // Configure CDPEngine parameters for ETH-A
        cdp_engine.set(ETH_A, "max_debt", 1_000_000 * WAD); // 1M debt ceiling
        cdp_engine.set(ETH_A, "min_debt", 2_000 * WAD); // 2000 min debt
        cdp_engine.set(ETH_A, "spot", 150 * RAY / 100); // 150% liquidation ratio

        // Configure Jug
        jug.init(ETH_A);
        jug.set("base_fee", RAY * 1 / 100); // 1% base stability fee
        jug.set("ds_engine", address(ds_engine));

        // Configure DSEngine parameters
        ds_engine.set(keccak256(abi.encode("surplus_auction_lot_size")), 10_000 * WAD);
        ds_engine.set(keccak256(abi.encode("debt_auction_bid_size")), 5_000 * WAD);
        ds_engine.set(keccak256(abi.encode("debt_auction_lot_size")), 5_000 * WAD);
        ds_engine.set(keccak256(abi.encode("min_surplus")), 1_000 * WAD);
        ds_engine.set(keccak256(abi.encode("pop_debt_delay")), 1 days);

        console.log("System initialization complete");
    }
}
