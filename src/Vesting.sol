// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./extensions/Ownable.sol";
import {IERC20} from "./interfaces/Interfaces.sol";

/// @dev Vesting Schedule: 12% day 1 then 8% every month thereafter.

/// @notice This contract will hold $PROVE tokens in escrow
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

    /// @param account        The wallet address of investor.
    /// @param tokensToVest   The total amount of $PROVE token allocated to that investor.
    /// @param tokensClaimed  The amount of tokens the investor has claimed already.
    struct Investor {
        address account;
        uint256 tokensToVest;
        uint256 tokensClaimed;
    }

    mapping(address => bool) public investors;        /// @notice Mapping to track investor addresses.
    // mapping(address => uint256) public tokensToVest;  /// @notice The total amount of $PROVE token allocated to that investor address.
    // mapping(address => uint256) public tokensClaimed; /// @notice The amount of tokens the investor has claimed already.

    // -----------
    // Constructor
    // -----------

    constructor(address _proveToken, address _admin) {
        proveToken = _proveToken;
        transferOwnership(_admin);
    }


    // ---------
    // Modifiers
    // ---------

    /// @dev modifier to check if msg.sender is an investor.
    modifier onlyInvestor() {
        require(investors[msg.sender] == true, "Vesting.sol::onlyInvestor() msg.sender must be an investor");
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
    /// @param account is the wallet address of investor that was added to the investorLibrary.
    event InvestorAdded(address indexed account);

    /// @notice This event is emitted when removeInvestor() is successfully executed.
    /// @param account is the wallet address of investor that was added to the investorLibrary.
    event InvestorRemoved(address indexed account);

    /// @notice This event is emitted when withdrawErc20() is executed.
    /// @param token address of Erc20 token.
    /// @param amount tokens withdrawn.
    /// @param receiver address of msg.sender.
    event Erc20TokensWithdrawn(address token, uint256 amount, address receiver);

    /// @notice This event is emitted when enableVesting() is executed. Should only be executed once.
    event VestingEnabled();


    // ---------
    // Functions
    // ---------

    /// @notice Used to claim vested tokens.
    /// @dev msg.sender must be the investor address
    function claim() external onlyInvestor() {
        require(vestingEnabled, "Vesting.sol::claim() vesting is not enabled");
        uint256 amountToClaim = getAmountToClaim(msg.sender);
        require(amountToClaim > 0, "Vesting.sol::claim() investor has no tokens to claim");

        // Transfer the tokens
        bool success = IERC20(proveToken).transfer(msg.sender, amountToClaim);
        require(success, "Vesting.sol::claim() transfer unsuccessful");

        // Get Investor position in array
        uint256 idx = locateInvestor(msg.sender);

        // Update Investor.tokensClaimed
        investorLibrary[idx].tokensClaimed = amountToClaim;

        emit ProveClaimed(msg.sender, amountToClaim);
    }


    // ---------------
    // Owner Functions
    // ---------------

    /// @notice This function sets an address as true in the investors mapping and also pushes a new investor element to the Investor array.
    /// @param _account the wallet address of investor being added.
    /// @param _tokensToVest the amount of $PROVE that is being vested for that investor.
    function addInvestor(address _account, uint256 _tokensToVest) external onlyOwner() {
        require(investors[_account] == false, "Vesting.sol::addInvestor() investor is already added");
        require(_account != address(0), "Vesting.sol::addInvestor() _account cannot be address(0)");
        require(_tokensToVest > 0, "Vesting.sol::addInvestor() _tokensToVest must be gt 0");

        investors[_account] = true;
        investorLibrary.push(Investor(_account, _tokensToVest, 0));
        
        emit InvestorAdded(_account);
    }

    /// @notice This function removes an investor from the investorLibrary.
    /// @param _account the wallet address of investor that is being removed.
    function removeInvestor(address _account) external onlyOwner() {
        require(_account != address(0), "Vesting.sol::removeInvestor() account cannot be address(0)");

        uint256 idx = locateInvestor(_account);

        Investor memory temp = investorLibrary[idx];
        investorLibrary[idx] = investorLibrary[investorLibrary.length-1];
        investorLibrary[investorLibrary.length-1] = temp;
        investorLibrary.pop();
        investors[_account] = false;

        emit InvestorRemoved(_account);
    }

    /// @notice This function starts the vesting period.
    /// @dev will set start time to vestingStartUnix.
    ///      will set vestingEnabled to true.
    function enableVesting() external onlyOwner() {
        require(!vestingEnabled, "Vesting.sol::enableVesting() vesting is already enabled");

        vestingEnabled = true;
        vestingStartUnix = block.timestamp;

        emit VestingEnabled();
    }

    /// @notice Is used to remove ERC20 tokens from the contract.
    /// @dev token address cannot be $PROVE
    /// @param token contract address of token we wish to remove.
    function withdrawErc20(address token) external onlyOwner() {
        require(token != proveToken, "Vesting.sol::withdrawErc20() cannot withdraw $PROVE token");
        require(token != address(0), "Vesting.sol::withdrawErc20() token cannot be address(0)");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "Vesting.sol::withdrawErc20() insufficient token balance");

        bool success = IERC20(token).transfer(owner(), balance);
        require(success, "Vesting.sol::withdrawErc20() transfer unsuccessful");

        emit Erc20TokensWithdrawn(token, balance, owner());
    }


    // ----
    // View
    // ----

    /// @notice This function returns the amount of tokens to claim for a specified investor.
    /// @param _account address of investor.
    /// @return uint256 amount of tokens to claim.
    function getAmountToClaim(address _account) public view returns (uint256) {
        if (investors[_account] && vestingEnabled) {

            uint256 idx = locateInvestor(_account);

            uint tokensToVest = getTokensToVest(_account);

            if (investorLibrary[idx].tokensClaimed >= tokensToVest) {
                return 0;
            }

            uint monthsPassed = ((block.timestamp - vestingStartUnix) / 4 weeks); 
            uint amountToClaim = (tokensToVest * 12 / 100) + (monthsPassed * (tokensToVest * 8 / 100));

            if (amountToClaim > tokensToVest) {
                amountToClaim = tokensToVest - investorLibrary[idx].tokensClaimed;
            }
            else {
                amountToClaim = amountToClaim - investorLibrary[idx].tokensClaimed;
            }

            return amountToClaim;
        }
        else {
            return 0;
        }
    }

    /// @notice This function returns the amount of tokens an investor HAS claimed.
    /// @param _account address of investor.
    /// @return uint256 amount of tokens claimed by account.
    function getAmountClaimed(address _account) public view returns (uint256) {
        if (investors[_account]) {

            uint256 idx = locateInvestor(_account);
            return investorLibrary[idx].tokensClaimed;
        }
        else {
            return 0;
        }
    }

    function getTokensToVest(address _account) public view returns (uint256) {
        if (investors[_account]) {

            uint256 idx = locateInvestor(_account);
            return investorLibrary[idx].tokensToVest;
        }
        else {
            return 0;
        }
    }

    function locateInvestor(address _account) internal view returns (uint256) {
        require(investors[_account] == true, "Vesting.sol::locateInvestor() account is not an investor");

        uint256 idx;

        for (uint256 i = 0; i < investorLibrary.length; i++) {
            if (investorLibrary[i].account == _account) {
                idx = i; 
                break;
            }
        }
        return idx;
    }

    function getInvestorLibrary() public view returns (Investor[] memory) {
        return investorLibrary;
    }
}
