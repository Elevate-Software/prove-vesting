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

    
}