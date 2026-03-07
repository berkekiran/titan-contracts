// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface IQuoter {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }
    
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }
    
    function quoteExactInputSingle(QuoteExactSingleParams memory params) 
        external returns (uint256 amountOut, uint256 gasEstimate);
}

contract TestQuoter is Script {
    address constant QUOTER = 0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xbA6720e72f929318E66AcED4389889640Aee0F6e;
    
    function run() external {
        IQuoter.PoolKey memory poolKey = IQuoter.PoolKey({
            currency0: WETH,
            currency1: TITAN,
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        
        IQuoter.QuoteExactSingleParams memory params = IQuoter.QuoteExactSingleParams({
            poolKey: poolKey,
            zeroForOne: true,
            exactAmount: 1000000000000000, // 0.001 WETH
            hookData: ""
        });
        
        vm.startBroadcast();
        
        try IQuoter(QUOTER).quoteExactInputSingle(params) returns (uint256 amountOut, uint256 gasEstimate) {
            console.log("AmountOut:", amountOut);
            console.log("GasEstimate:", gasEstimate);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        } catch (bytes memory data) {
            console.log("Raw revert data length:", data.length);
            if (data.length >= 64) {
                (uint256 amountOut, uint256 gasEstimate) = abi.decode(data, (uint256, uint256));
                console.log("AmountOut (from revert):", amountOut);
                console.log("GasEstimate (from revert):", gasEstimate);
            }
        }
        
        vm.stopBroadcast();
    }
}
