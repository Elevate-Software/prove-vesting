// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "./Utility.sol";

// Import sol files.
import { TaxToken } from "../src/TaxToken.sol";
import { Treasury } from "../src/Treasury.sol";
import { Vesting }  from "../src/Vesting.sol";

contract VestingTest is Utility, Test {
    Vesting vesting;

    function setUp() public {
        createActors();
        setUpTokens();

        // (1) Deploy the TaxToken.
        proveToken = new TaxToken(
            1_000_000_000,     // Initial liquidity (220M)
            'Prove Zero',      // Name of token
            'PROVE',           // Symbol of token
            18,                // Precision of decimals
            220_000_000,       // Max wallet (220M)
            220_000_000        // Max transaction (220M)
        );

        // (2) Deploy the Treasury.
        treasury = new Treasury(
            address(this),
            address(proveToken),
            USDC
        );

        // (3) Update the TaxToken "treasury" state variable.
        proveToken.setTreasury(address(treasury));

        // Finally, deploy Vesting contract
        vesting = new Vesting(
            address(proveToken),  
            address(dev)
        );
    }

    // Initial State Test.
    function test_vesting_init_state() public {
        assertEq(vesting.proveToken(),       address(proveToken));
        assertEq(vesting.vestingStartUnix(), 0);
        assertEq(vesting.vestingEnabled(),   false);
    }

    // ~ enableVesting() tests ~

    /// @dev Verifies enableVesting restrictions.
    function test_vesting_enableVesting_restrictions() public {
        // Jon should NOT be able to call enableVesting()
        assert(!jon.try_enableVesting(address(vesting)));

        // Joe should NOT be able to call enableVesting()
        assert(!joe.try_enableVesting(address(vesting)));

        // Dev should result in a successful execution of enableVesting()
        assert(dev.try_enableVesting(address(vesting)));

        // Dev should NOT be able to call enableVesting() after enableVesting has been enabled
        assert(!dev.try_enableVesting(address(vesting)));
    }

    /// @dev Verifies enableVesting state changes.
    function test_vesting_enableVesting_state_changes() public {
        // Pre-State check.
        assertEq(vesting.vestingStartUnix(), 0);
        assertEq(vesting.vestingEnabled(),   false);

        // Call enableVesting().
        assert(dev.try_enableVesting(address(vesting)));

        // Post-State check.
        assertEq(vesting.vestingStartUnix(), block.timestamp);
        assertEq(vesting.vestingEnabled(),   true);
    }

    // ~ withdrawErc20() tests ~

    /// @dev Verifies withdrawErc20 restrictions.
    function test_vesting_withdrawErc20_restrictions() public {
        // Jon should NOT be able to call withdrawErc20()
        assert(!jon.try_withdrawErc20(address(vesting), USDC));

        // Joe should NOT be able to call withdrawErc20()
        assert(!joe.try_withdrawErc20(address(vesting), USDC));

        // Dev should NOT be able to withdraw from a 0 balance
        assert(!dev.try_withdrawErc20(address(vesting), USDC));

        // Dev should NOT be able to withdraw $PROVE token
        assert(!dev.try_withdrawErc20(address(vesting), vesting.proveToken()));

        // Dev should NOT be able to withdraw address(0)
        assert(!dev.try_withdrawErc20(address(vesting), address(0)));

        // deal 100 USDC to the vesting contract
        deal(USDC, address(vesting), 100 * USD);

        // Dev should be able to withdraw 100 USDC from the vesting contract
        assert(dev.try_withdrawErc20(address(vesting), USDC));
    }

    /// @dev Verifies withdrawErc20 state changes.
    function test_vesting_withdrawErc20_state_changes() public {
        deal(USDC, address(vesting), 100 * USD);

        // Pre-State check
        assertEq(IERC20(USDC).balanceOf(address(vesting)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(address(dev)),     0);

        // Dev is going to call withdrawErc20
        assert(dev.try_withdrawErc20(address(vesting), USDC));

        // Post-State check
        assertEq(IERC20(USDC).balanceOf(address(vesting)), 0);
        assertEq(IERC20(USDC).balanceOf(address(dev)),     100 * USD);
    }

    // ~ addInvestor() tests ~

    /// @dev Verifies addInvestor restrictions
    function test_vesting_addInvestor_restrictions() public {
        // Exploiter Jon should NOT be able to call addInvestor()
        assert(!jon.try_addInvestor(address(vesting), address(joe), 10 ether));

        // Investor Joe should NOT be able to call addInvestor()
        assert(!joe.try_addInvestor(address(vesting), address(joe), 10 ether));

        // Dev should be able to call addInvestor()
        assert(dev.try_addInvestor(address(vesting), address(joe), 10 ether));

        vm.startPrank(address(dev));

        // Dev should NOT be able to add the same investor twice
        vm.expectRevert("Vesting.sol::addInvestor() investor is already added");
        vesting.addInvestor(address(joe), 10 ether);

        // Dev should NOT be able to add address(0) as a param
        vm.expectRevert("Vesting.sol::addInvestor() _account cannot be address(0)");
        vesting.addInvestor(address(0), 10 ether);

        // Dev should NOT be able to add 0 tokens as a param
        vm.expectRevert("Vesting.sol::addInvestor() _tokensToVest must be gt 0");
        vesting.addInvestor(address(jon), 0);

        vm.stopPrank();
    }

    /// @dev Verifies addInvestor state changes
    function test_vesting_addInvestor_state_changes() public {
        // Pre-State check.
        assertEq(vesting.investors(address(joe)),      false);
        Vesting.Investor[] memory tempArr = vesting.getInvestorLibrary();
        assertEq(tempArr.length,          0);

        // Call addInvestor().
        assert(dev.try_addInvestor(address(vesting), address(joe), 10 ether));

        // Post-State check.
        assertEq(vesting.investors(address(joe)),      true);
        tempArr = vesting.getInvestorLibrary();
        assertEq(tempArr.length,           1);
        assertEq(tempArr[0].account,       address(joe));
        assertEq(tempArr[0].tokensToVest,  10 ether);
        assertEq(tempArr[0].tokensClaimed, 0);
    }

    // ~ removeInvestor() tests ~

    /// @dev Verifies removeInvestor() restrictions
    function test_vesting_removeInvestor_restrictions() public {
        //add an investor so we can test removing it
        assert(dev.try_addInvestor(address(vesting), address(joe), 10 ether));

        // Exploiter Jon should NOT be able to call removeInvestor()
        assert(!jon.try_removeInvestor(address(vesting), address(joe)));

        // Investor Joe should NOT be able to call removeInvestor()
        assert(!joe.try_removeInvestor(address(vesting), address(joe)));

        // Dev should be able to call removeInvestor()
        assert(dev.try_removeInvestor(address(vesting), address(joe)));

        vm.startPrank(address(dev));

        //Dev should not be able to remove an account that is not an investor
        vm.expectRevert("Vesting.sol::locateInvestor() account is not an investor");
        vesting.removeInvestor(address(jon));

        //Dev should not be able to remove account address(0)
        vm.expectRevert("Vesting.sol::removeInvestor() account cannot be address(0)");
        vesting.removeInvestor(address(0));

        vm.stopPrank();
    }

    /// @dev Verifies removeInvestor() state changes
    function test_vesting_removeInvestor_state_changes() public {
        //add an investor so we can test removing it
        assert(dev.try_addInvestor(address(vesting), address(joe), 10 ether));

        // Pre-State check.
        assertEq(vesting.investors(address(joe)),      true);
        Vesting.Investor[] memory tempArr = vesting.getInvestorLibrary();
        assertEq(tempArr.length,          1);
        assertEq(tempArr[0].account,       address(joe));
        assertEq(tempArr[0].tokensToVest,  10 ether);
        assertEq(tempArr[0].tokensClaimed, 0);

        // Call removeInvestor()
        assert(dev.try_removeInvestor(address(vesting), address(joe)));

        // Post-State check.
        assertEq(vesting.investors(address(joe)),      false);
        tempArr = vesting.getInvestorLibrary();
        assertEq(tempArr.length,          0);
    }

    /// @dev Verifies removeInvestor() pops elements correctly from investorLibrary[]
    function test_vesting_removeInvestor_largeArray() public {
        Actor tim = new Actor();

        //add an investor so we can test removing it
        assert(dev.try_addInvestor(address(vesting), address(joe), 10 ether));
        assert(dev.try_addInvestor(address(vesting), address(jon), 20 ether));
        assert(dev.try_addInvestor(address(vesting), address(tim), 30 ether));

        // Pre-State check.
        assertEq(vesting.investors(address(joe)),      true);
        assertEq(vesting.investors(address(jon)),      true);
        assertEq(vesting.investors(address(tim)),      true);
        Vesting.Investor[] memory tempArr = vesting.getInvestorLibrary();
        assertEq(tempArr.length,          3);
        assertEq(tempArr[0].account,       address(joe));
        assertEq(tempArr[0].tokensToVest,  10 ether);
        assertEq(tempArr[0].tokensClaimed, 0);
        assertEq(tempArr[1].account,       address(jon));
        assertEq(tempArr[1].tokensToVest,  20 ether);
        assertEq(tempArr[1].tokensClaimed, 0);
        assertEq(tempArr[2].account,       address(tim));
        assertEq(tempArr[2].tokensToVest,  30 ether);
        assertEq(tempArr[2].tokensClaimed, 0);

        // Call removeInvestor()
        assert(dev.try_removeInvestor(address(vesting), address(joe)));

        // Post-State check.
        assertEq(vesting.investors(address(joe)),      false);
        assertEq(vesting.investors(address(jon)),      true);
        assertEq(vesting.investors(address(tim)),      true);
        tempArr = vesting.getInvestorLibrary();
        assertEq(tempArr.length,          2);
        assertEq(tempArr[0].account,       address(tim));
        assertEq(tempArr[0].tokensToVest,  30 ether);
        assertEq(tempArr[0].tokensClaimed, 0);
        assertEq(tempArr[1].account,       address(jon));
        assertEq(tempArr[1].tokensToVest,  20 ether);
        assertEq(tempArr[1].tokensClaimed, 0);
    }

    // ~ getAmountToClaim() tests ~\

    /// @dev Verifies getAmountToClaim() restrictions
    function test_vesting_getAmountToClaim_restrictions() public {
        // Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), 20 ether));

        // Verify getAmountToClaim is 0 since vesting has not begun
        assertEq(vesting.getAmountToClaim(address(jon)), 0);

        // Enable vesting
        dev.try_enableVesting(address(vesting));

        // Should return 0 for Joe since account isn't an investor
        assertEq(vesting.getAmountToClaim(address(joe)), 0);

        // Verify address(0) returns 0
        assertEq(vesting.getAmountToClaim(address(0)), 0);
    }

    /// @dev Verifies getAmountToClaim()
    function test_vesting_getAmountToClaim() public {
        //1 Million prove tokens (same decimals as ether 10**18)
        uint256 _amount = 1_000_000 ether;

        // Add investor Jon
        assert(dev.try_addInvestor(address(vesting), address(jon), _amount));

        // Verify tokensToVest == _amount
        assertEq(vesting.getTokensToVest(address(jon)), _amount);

        // Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Skip 3 months
        skip(12 weeks);

        // Verify amountToClaim(jon) after 3 months
        uint256 toClaim = (_amount * 12 / 100) + (3 * (_amount * 8 / 100));
        assertEq(vesting.getAmountToClaim(address(jon)), toClaim);

        // Skip 8 months to get to 11 (should be 100% of tokensToVest now)
        skip(32 weeks);

        // Verify amountToClaim(jon) after 11 months
        toClaim = (_amount * 12 / 100) + (11 * (_amount * 8 / 100));
        assertEq(vesting.getAmountToClaim(address(jon)), toClaim);
        assertEq(vesting.getAmountToClaim(address(jon)), _amount);
    }

    // ~ claim() tests ~

    /// @dev Verifies claim() restrictions
    function test_vesting_claim_restrictions() public {
        // *First fill up the contract with PROVE tokens 
        deal(proveToken, address(vesting), 5_000_000 ether);

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
    function test_vesting_claim_state_changes() public {
        uint _amount = 1_000_000 ether;

        // *First fill up the contract with PROVE tokens 
        deal(vesting.proveToken, address(vesting), _amount);

        //Jon is trying to claim
        vm.startPrank(address(jon));

        //Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), _amount));

        //Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Pre-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), 0);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 12 / 100);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 20 / 100);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 28 / 100);

        // Skip 12 weeks
        skip(12 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 52 / 100);

        // Skip 24 weeks
        skip(24 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount);

        vm.stopPrank();
    }

    /// @dev Verifies claim() edge cases
    function test_vesting_claim_edge_cases() public {
        // *First fill up the contract with PROVE tokens 
        deal(vesting.proveToken, address(vesting), 5_000_000 ether);

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
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), (1_000_000 ether * 12 / 100) );

        // Skip another 22 weeks to 6 months total
        skip(22 weeks);
        // Joe is trying to claim some in the middle
        assert(joe.try_claim(address(vesting)));

        // Joe should have only gotten 60% of his tokensToVest
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(joe)), (1_000_000 ether * 60 / 100));

        // Skip another 20 weeks to 11 months total
        skip(20 weeks);
        // Joe is going to claim again and it should be the rest of his tokens
        assert(joe.try_claim(address(vesting)));

        // Joe should have 100% of his tokensToVest
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(joe)), (1_000_000 ether));

        // Skip a year forward
        skip(52 weeks);
        // Dev is going to claim far after the end of the vesting schedule
        assert(dev.try_claim(address(vesting)));

        // Dev should have 100% of their tokens but no more
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(dev)), (1_000_000 ether));

    }

    /// @dev Verifies claim() state changes using fuzzing
    function test_vesting_claim_fuzzing1(uint256 _amount) public {
        _amount = bound(_amount, 100_000 ether, 100_000_000 ether);

        // *First fill up the contract with PROVE tokens 
        deal(vesting.proveToken, address(vesting), _amount);

        //Jon is trying to claim
        vm.startPrank(address(jon));

        //Add jon as investor
        assert(dev.try_addInvestor(address(vesting), address(jon), _amount));

        //Enable vesting
        assert(dev.try_enableVesting(address(vesting)));

        // Pre-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), 0);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 12 / 100, 1 ether);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 20 / 100, 1 ether);

        // Skip 4 weeks
        skip(4 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 28 / 100, 1 ether);

        // Skip 12 weeks
        skip(12 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        withinDiff(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount * 52 / 100, 1 ether);

        // Skip 24 weeks
        skip(24 weeks);

        // Jon is going to call claim
        assert(jon.try_claim(address(vesting)));

        // Post-State check
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(jon)), _amount);

        vm.stopPrank();
    }

    /// @dev Verifies claim() edge cases using fuzzing
    function test_vesting_claim_fuzzing2(uint256 _amount) public {
        _amount = bound(_amount, 100_000 ether, 100_000_000 ether);

        // *First fill up the contract with PROVE tokens 
        deal(vesting.proveToken, address(vesting), _amount * 3);

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
        withinDiff(IERC20(vesting.proveToken()).balanceOf(address(jon)), (_amount * 12 / 100), 1 ether);

        // Skip another 22 weeks to 6 months total
        skip(22 weeks);
        // Joe is trying to claim some in the middle
        assert(joe.try_claim(address(vesting)));

        // Joe should have only gotten 60% of his tokensToVest
        withinDiff(IERC20(vesting.proveToken()).balanceOf(address(joe)), (_amount * 60 / 100), 1 ether);

        // Skip another 20 weeks to 11 months total
        skip(20 weeks);
        // Joe is going to claim again and it should be the rest of his tokens
        assert(joe.try_claim(address(vesting)));

        // Joe should have 100% of his tokensToVest
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(joe)), _amount);

        // Skip a year forward
        skip(52 weeks);
        // Dev is going to claim far after the end of the vesting schedule
        assert(dev.try_claim(address(vesting)));

        // Dev should have 100% of their tokens but no more
        assertEq(IERC20(vesting.proveToken()).balanceOf(address(dev)), _amount);

    }

}
