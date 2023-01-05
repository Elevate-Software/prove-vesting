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

    // Verifies enableVesting restrictions.
    function test_vesting_enableVesting_restrictions() public {
        // Jon should NOT be able to call enableVesting()
        assert(!jon.try_enableVesting(address(vesting)));

        // Joe should NOT be able to call enableVesting()
        assert(!joe.try_enableVesting(address(vesting)));

        // Dev should result in a successful execution of enableVesting()
        assert(dev.try_enableVesting(address(vesting)));
    }

    // Verifies enableVesting state changes.
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
}
