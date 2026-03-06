// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface IStateView {
    function getSlot0(bytes32 poolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
    function getLiquidity(bytes32 poolId) external view returns (uint128);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract CheckPool is Script {
    address constant TITAN = 0x33b2bB827eC6b3595e452210766745A05858E9De;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant STATE_VIEW = 0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C;
    address constant LIQUIDITY_ROUTER = 0xf397064DBd74ab1869744e1661045CA8805044b1;
    address constant USER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    
    function run() external view {
        // Currency0 = TITAN (0x33...), Currency1 = WETH (0x7b...)
        bytes32 poolId = keccak256(abi.encode(TITAN, WETH, uint24(3000), int24(60), address(0)));
        console.log("PoolId:", vm.toString(poolId));
        
        // Check pool state
        IStateView stateView = IStateView(STATE_VIEW);
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = stateView.getSlot0(poolId);
        uint128 liquidity = stateView.getLiquidity(poolId);
        
        console.log("sqrtPriceX96:", sqrtPriceX96);
        console.log("tick:", tick);
        console.log("protocolFee:", protocolFee);
        console.log("lpFee:", lpFee);
        console.log("liquidity:", liquidity);
        console.log("Pool initialized:", sqrtPriceX96 > 0);
        
        // Check allowances
        uint256 titanAllowance = IERC20(TITAN).allowance(USER, LIQUIDITY_ROUTER);
        uint256 wethAllowance = IERC20(WETH).allowance(USER, LIQUIDITY_ROUTER);
        
        console.log("");
        console.log("User TITAN allowance to LiquidityRouter:", titanAllowance / 1e18);
        console.log("User WETH allowance to LiquidityRouter:", wethAllowance / 1e18);
        
        // Check balances
        uint256 titanBalance = IERC20(TITAN).balanceOf(USER);
        uint256 wethBalance = IERC20(WETH).balanceOf(USER);
        
        console.log("");
        console.log("User TITAN balance:", titanBalance / 1e18);
        console.log("User WETH balance:", wethBalance / 1e18);
    }
}
