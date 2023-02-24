// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface ITreasury {
    function updateTaxesAccrued(uint amt) external;
}

interface IVesting {
    function getAllVestedTokens() external view returns (uint256 amount);
}