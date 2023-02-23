// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "./Utility.sol";

// Import sol files.
import { TaxToken } from "../src/TaxToken.sol";
import { Treasury } from "../src/Treasury.sol";
import { Vesting }  from "../src/Vesting.sol";

contract MainDeploymentTest is Utility, Test {
    Vesting vesting;
    TaxToken proveToken;
    Treasury treasury;

    function setUp() public {
        createActors();
        setUpTokens();

        /// @dev Don't need to set up token with treasury because vesting contract should be whitelisted.

        // Deploy the TaxToken.
        proveToken = new TaxToken(
            1_000_000_000,     // Initial liquidity (220M)
            'Prove Zero',      // Name of token
            'PROVE',           // Symbol of token
            18,                // Precision of decimals
            1_000_000_000,     // Max wallet (220M)
            1_000_000_000      // Max transaction (220M)
        );
        
        // IDEALLY add investors here.

        // Finally, deploy Vesting contract.
        vesting = new Vesting(
            address(proveToken),  
            address(dev)
        );
        
        // Set vesting address on token.
        proveToken.setVesting(address(vesting));
    }

    // Initial State Test.
    function test_mainDeploymentTest_init_state() public {
        assertEq(proveToken.totalSupply(),     1_000_000_000 ether);
        assertEq(proveToken.balanceOf(address(this)),    1_000_000_000 ether);
        assertEq(proveToken.balanceOf(address(vesting)), 0);
        assertEq(proveToken.owner(),    address(this));
        assertEq(proveToken.vesting(),  address(vesting));
        assertEq(proveToken.whitelist(proveToken.vesting()),   true);
        assertEq(proveToken.whitelist(address(proveToken)),    true);
        assertEq(proveToken.whitelist(proveToken.owner()),     true);

        assertEq(vesting.proveToken(),       address(proveToken));
        assertEq(vesting.vestingStartUnix(), 0);
        assertEq(vesting.vestingEnabled(),   false);
        assertEq(vesting.owner(),  address(dev));
    }

    /// @dev Verifies claim() state changes
    function test_mainDeploymentTest_claim() public {
        uint _amount = 1_000_000 ether;

        // Transfer PROVE tokens to vesting contract
        proveToken.transfer(address(vesting), _amount);

        // Jon is trying to claim
        vm.startPrank(address(jon));

        // Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), _amount));

        // Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Pre-State check
        assertEq(proveToken.balanceOf(address(jon)), 0);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(proveToken.balanceOf(address(jon)), _amount * 12 / 100);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(proveToken.balanceOf(address(jon)), _amount * 20 / 100);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(proveToken.balanceOf(address(jon)), _amount * 28 / 100);

        // Skip 12 weeks
        skip(12 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(proveToken.balanceOf(address(jon)), _amount * 52 / 100);

        // Skip 24 weeks
        skip(24 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(proveToken.balanceOf(address(jon)), _amount);

        vm.stopPrank();
    }

}
