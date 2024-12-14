// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface IOracle {
    // --- Events ---
    event LogValue(bytes32 val);

    // --- State Variables ---
    function stopped() external view returns (bool);
    function maxStaleness() external view returns (uint16);
    function whitelisted(address) external view returns (bool);

    // --- Core Functions ---
    function peek() external view returns (bytes32, bool);
    function poke(bytes[] calldata priceUpdate) external payable;

    // --- Admin Functions ---
    function stop() external;
    function start() external;
    function setMaxStaleness(uint16 _maxStaleness) external;
    function add_whitelist(address a) external;
    function remove_whitelist(address a) external;
}
