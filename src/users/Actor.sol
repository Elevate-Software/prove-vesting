// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import { IERC20 } from "../interfaces/Interfaces.sol";

contract Actor {

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/


    //////////////////////////////////////////////////////////////////////////
    ///                             PROVE VESTING                          ///
    //////////////////////////////////////////////////////////////////////////


    function try_enableVesting(address _contract) external returns (bool ok) {
        string memory sig = "enableVesting()";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig));
    }

    function try_withdrawErc20(address _contract, address token) external returns (bool ok) {
        string memory sig = "withdrawErc20(address)";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig, token));
    }

    /// @notice Ensure, when creating the sig -> leave no spaces between param data types.
    function try_addInvestor(address _contract, address account, uint256 tokensToVest) external returns (bool ok) {
        string memory sig = "addInvestor(address,uint256)";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig, account, tokensToVest));
    }

    function try_removeInvestor(address _contract, address account) external returns (bool ok) {
        string memory sig = "removeInvestor(address)";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig, account));
    }

    function try_getAmountToClaim(address _contract, address account) external returns (bool ok) {
        string memory sig = "getAmountToClaim(address)";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig, account));
    }

    function try_claim(address _contract) external returns (bool ok) {
        string memory sig = "claim()";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig));
    }

}