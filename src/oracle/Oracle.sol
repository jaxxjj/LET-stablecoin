// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {Auth} from "../lib/Auth.sol";

contract Oracle is Auth {
    bool public stopped;

    IPyth public immutable pyth;
    bytes32 public immutable priceFeedId;
    uint16 public maxStaleness = 3600; // 1 hour

    struct Feed {
        int64 price;
        uint64 conf;
        bool has_value;
    }

    Feed public cur;
    mapping(address => bool) public whitelisted;

    constructor(address _pythContract, bytes32 _priceFeedId) {
        pyth = IPyth(_pythContract);
        priceFeedId = _priceFeedId;
    }

    modifier not_stopped() {
        require(!stopped, "stopped");
        _;
    }

    modifier only_whitelisted() {
        require(whitelisted[msg.sender], "not whitelisted");
        _;
    }

    function poke(bytes[] calldata priceUpdate) external payable not_stopped {
        uint256 fee = pyth.getUpdateFee(priceUpdate);
        require(msg.value >= fee, "insufficient fee");

        pyth.updatePriceFeeds{value: fee}(priceUpdate);

        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceFeedId, maxStaleness);
        cur = Feed(price.price, price.conf, true);

        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function peek() external view only_whitelisted returns (bytes32, bool) {
        if (!cur.has_value) return (bytes32(0), false);
        return (bytes32(uint256(uint64(cur.price))), true);
    }

    function stop() external auth {
        stopped = true;
    }

    function start() external auth {
        stopped = false;
    }

    function setMaxStaleness(uint16 _maxStaleness) external auth {
        maxStaleness = _maxStaleness;
    }

    function add_whitelist(address a) external auth {
        require(a != address(0), "address = 0");
        whitelisted[a] = true;
    }

    function remove_whitelist(address a) external auth {
        whitelisted[a] = false;
    }
}
