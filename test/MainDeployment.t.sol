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

    // ~ claim() tests ~

    /// @dev Verifies claim() restrictions
    function test_mainDeploymentTest_claim_restrictions() public {
        uint _amount = 5_000_000 ether;

        // Transfer PROVE tokens to vesting contract
        proveToken.transfer(address(vesting), _amount);

        // Jon is trying to claim
        vm.startPrank(address(jon));

        // Should not work if caller isn't investor
        vm.expectRevert("Vesting.sol::onlyInvestor() msg.sender must be an investor");
        vesting.claim();

        // Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), 1_000_000 ether));

        // Should not work if vesting isn't enabled
        vm.expectRevert("Vesting.sol::claim() vesting is not enabled");
        vesting.claim();

        // Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Jon can claim his tokens
        vesting.claim();

        skip(52 weeks);

        // Jon can claim more tokens
        vesting.claim();

        vm.expectRevert("Vesting.sol::claim() investor has no tokens to claim");
        vesting.claim();

        vm.stopPrank();

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

    /// @dev Verifies claim() edge cases
    function test_mainDeploymentTest_claim_edge_cases() public {
        uint _amount = 5_000_000 ether;

        proveToken.transfer(address(vesting), _amount);

        //Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Adding three investors for three edge cases 
        // Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), 1_000_000 ether));

        // Add joe as investor
        assert(dev.try_addInvestor(address(vesting), address(joe), 1_000_000 ether));

        // Add dev as investor
        assert(dev.try_addInvestor(address(vesting), address(dev), 1_000_000 ether));

        // Jon is trying to claim after less than one month.
        skip(2 weeks);
        assert(jon.try_claim(address(vesting)));

        // Jon should have only gotten 12% of his tokensToVest
        assertEq(proveToken.balanceOf(address(jon)), (1_000_000 ether * 12 / 100) );

        // Skip another 22 weeks to 6 months total
        skip(22 weeks);
        // Joe is trying to claim some in the middle
        assert(joe.try_claim(address(vesting)));

        // Joe should have only gotten 60% of his tokensToVest
        assertEq(proveToken.balanceOf(address(joe)), (1_000_000 ether * 60 / 100));

        // Skip another 20 weeks to 11 months total
        skip(20 weeks);
        // Joe is going to claim again and it should be the rest of his tokens
        assert(joe.try_claim(address(vesting)));

        // Joe should have 100% of his tokensToVest
        assertEq(proveToken.balanceOf(address(joe)), (1_000_000 ether));

        // Skip a year forward
        skip(52 weeks);
        // Dev is going to claim far after the end of the vesting schedule
        assert(dev.try_claim(address(vesting)));

        // Dev should have 100% of their tokens but no more
        assertEq(proveToken.balanceOf(address(dev)), (1_000_000 ether));

    }

    /// @dev Verifies claim() state changes using fuzzing
    function test_mainDeploymentTest_claim_fuzzing1(uint256 _amount) public {
        _amount = bound(_amount, 100_000 ether, 100_000_000 ether);

        // First fill up the contract with PROVE tokens 
        proveToken.transfer(address(vesting), _amount);

        //Jon is trying to claim
        vm.startPrank(address(jon));

        //Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), _amount));

        //Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Pre-State check
        assertEq(proveToken.balanceOf(address(jon)), 0);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(proveToken.balanceOf(address(jon)), _amount * 12 / 100, 1 ether);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(proveToken.balanceOf(address(jon)), _amount * 20 / 100, 1 ether);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(proveToken.balanceOf(address(jon)), _amount * 28 / 100, 1 ether);

        // Skip 12 weeks
        skip(12 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(proveToken.balanceOf(address(jon)), _amount * 52 / 100, 1 ether);

        // Skip 24 weeks
        skip(24 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(proveToken.balanceOf(address(jon)), _amount);

        vm.stopPrank();
    }

    /// @dev Verifies claim() edge cases using fuzzing
    function test_mainDeploymentTest_claim_fuzzing2(uint256 _amount) public {
        _amount = bound(_amount, 100_000 ether, 100_000_000 ether);

        // First fill up the contract with PROVE tokens 
        proveToken.transfer(address(vesting), _amount*3);

        //Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Adding three investors for three edge cases 
        // Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), _amount));

        // Add joe as investor
        assert(dev.try_addInvestor(address(vesting), address(joe), _amount));

        // Add dev as investor
        assert(dev.try_addInvestor(address(vesting), address(dev), _amount));

        // Jon is trying to claim after less than one month.
        skip(2 weeks);
        assert(jon.try_claim(address(vesting)));

        // Jon should have only gotten 12% of his tokensToVest
        withinDiff(proveToken.balanceOf(address(jon)), (_amount * 12 / 100), 1 ether);

        // Skip another 22 weeks to 6 months total
        skip(22 weeks);
        // Joe is trying to claim some in the middle
        assert(joe.try_claim(address(vesting)));

        // Joe should have only gotten 60% of his tokensToVest
        withinDiff(proveToken.balanceOf(address(joe)), (_amount * 60 / 100), 1 ether);

        // Skip another 20 weeks to 11 months total
        skip(20 weeks);
        // Joe is going to claim again and it should be the rest of his tokens
        assert(joe.try_claim(address(vesting)));

        // Joe should have 100% of his tokensToVest
        assertEq(proveToken.balanceOf(address(joe)), _amount);

        // Skip a year forward
        skip(52 weeks);
        // Dev is going to claim far after the end of the vesting schedule
        assert(dev.try_claim(address(vesting)));

        // Dev should have 100% of their tokens but no more
        assertEq(proveToken.balanceOf(address(dev)), _amount);

    }

}
