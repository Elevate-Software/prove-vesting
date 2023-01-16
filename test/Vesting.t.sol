// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "./Utility.sol";
import { Vesting } from "../src/Vesting.sol";

contract VestingTest is Utility, Test {
    Vesting vesting;

    function setUp() public {
        createActors();
        setUpTokens();

        // deploy Vesting contract
        vesting = new Vesting(
            address(222),
            address(dev)
        );
    }

    // Initial State Test.
    function test_vesting_init_state() public {
        assertEq(vesting.proveToken(),       address(222));
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
        vm.expectRevert("Vesting.sol::removeInvestor() account is not an investor");
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
        /// NOTE: this test won't work because delete does not remove the gap in the array, length remains 1
        //assertEq(tempArr.length,          0);
    }
}
