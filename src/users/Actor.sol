// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import { IERC20 } from "../interfaces/Interfaces.sol";

contract Actor {

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/


    //////////////////////////////////////////////////////////////////////////
    ///                             GOGE TOKEN                             ///
    //////////////////////////////////////////////////////////////////////////


    function try_enableVesting(address _contract) external returns (bool ok) {
        string memory sig = "enableVesting()";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig));
    }

    function try_withdrawErc20(address _contract, address token) external returns (bool ok) {
        string memory sig = "withdrawErc20(address)";
        (ok,) = address(_contract).call(abi.encodeWithSignature(sig, token));
    }

}