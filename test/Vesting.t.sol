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


}
