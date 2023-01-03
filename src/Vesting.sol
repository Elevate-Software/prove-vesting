// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./extensions/Ownable.sol";
import {IERC20} from "./interfaces/Interfaces.sol";

/// @dev Vesting Schedule: 12% day 1 then 8% every month thereafter.

/// @notice This contract will hold $PROVE tokens in eskrow
///         This contract will facilitate the private sale investor vesting tokens
///         This contract will follow a strict vesting schedule
///         This contract will follow a claim model
contract Vesting is Ownable {

    // ---------------
    // State Variables
    // ---------------

    address public immutable proveToken;  /// @notice The vested token address.

    uint256 public vestingStartUnix;  /// @notice block timestamp of when vesting has begun
    bool public vestingEnabled;       /// @notice vesting enabled when true.

    Investor[] investorLibrary;   /// @notice array of investors.

    /// @param tokensToVest   The total amount of $PROVE token allocated to that investor.
    /// @param tokensClaimed  The amount of tokens the investor has claimed already.
    struct Investor {
        uint256 tokensToVest;
        uint256 tokensClaimed;
    }


    // -----------
    // Constructor
    // -----------

    constructor(address _proveToken) {
        proveToken = _proveToken;
    }


    // ---------
    // Modifiers
    // ---------

    /// @dev modifier to check if msg.sender is an investor.
    modifier onlyInvestor() {
        // TODO: Add requirement
        _;
    }


    // ------
    // Events
    // ------

    /// @notice This event is emitted when claim() is successfully executed.
    /// @param account is the wallet address of msg.sender.
    /// @param amountClaimed is the amount of tokens the account claimed.
    event ProveClaimed(address account, uint256 amountClaimed);

    /// @notice This event is emitted when addInvestor() is successfully executed.
    /// @param account is the wallet address of investor that was addes to the investorLibrary.
    event investorAdded(address account);

    /// @notice This event is emitted when withdrawErc20() is executed.
    /// @param token address of Erc20 token.
    /// @param amount tokens withdrawn.
    /// @param receiver address of msg.sender.
    event Erc20TokensWithdrawn(address token, uint256 amount, address receiver);


    // ---------
    // Functions
    // ---------

    /// @notice Used to claim vested tokens.
    /// @dev msg.sender must be the investor address
    function claim() external onlyInvestor() {}


    // ---------------
    // Owner Functions
    // ---------------

    /// @notice This function adds an address to the investorLibrary.
    /// @param account the wallet address of investor being added.
    /// @param tokensToVest the amount of $PROVE that is being vested for that investor.
    function addInvestor(address account, uint256 tokensToVest) external onlyOwner() {}

    /// @notice This function removes an investor from the investorLibrary.
    /// @param account the wallet address of investor that is being removed.
    function removeInvestor(address account) external onlyOwner() {}

    /// @notice This function starts the vesting period.
    /// @dev will set start time to vestingStartUnix.
    ///      will set vestingEnabled to true.
    function enableVesting() external onlyOwner() {}

    /// @notice Is used to remove ERC20 tokens from the contract.
    /// @dev token address cannot be $PROVE
    /// @param token contract address of token we wish to remove.
    function withdrawErc20(address token) external onlyOwner() {}


    // ----
    // View
    // ----

    /// @notice This function returns the amount of tokens to claim for a specified investor.
    /// @param account  address of investor.
    /// @return uint256 amount of tokens to claim.
    function getAmountToClaim(address account) public view returns (uint256) {}

    /// @notice This function returns the amount of tokens an investor HAS claimed.
    /// @param account address of investor.
    /// @return uint256 amount of tokens claimed by account.
    function getAmountClaimed(address account) public view returns (uint256) {}

    /// @notice This function returns the specified account's position on the investorLibrary
    /// @dev If bool is returned false, investor does not exist.
    /// @param account address of investor.
    /// @return bool true if investor exists, false otherwise.
    /// @return uint256 index in investorLibrary that the account exists.
    function isInvestor(address account) public view returns (bool, uint256) {}

}
