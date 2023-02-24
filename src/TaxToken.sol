//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import { IERC20 } from "./interfaces/IERC20.sol";
import { ITreasury, IVesting } from "./interfaces/InterfacesAggregated.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router.sol";
import { ERC20 } from "./interfaces/ERC20.sol";
import "./extensions/Ownable.sol";

/// @dev    The TaxToken is responsible for supporting generic ERC20 functionality including ERC20Pausable functionality.
///         The TaxToken will generate taxes on transfer() and transferFrom() calls for non-whitelisted addresses.
///         The Admin can specify the tax fee in basis points for buys, sells, and transfers.
///         The TaxToken will forward all taxes generated to a Treasury
contract TaxToken is ERC20, Ownable {
 
    // ---------------
    // State Variables
    // ---------------

    // ERC20 Basic
    uint256 _totalSupply;
    //uint8 private _decimals;
    string private _name;
    string private _symbol;

    // ERC20 Pausable state
    bool private _paused;

    // Extras
    address public treasury;
    address public vesting;
    address public depositor;

    address public constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public immutable UNISWAP_V2_PAIR;

    bool public taxesRemoved;   /// @dev Once true, taxes are permanently set to 0 and CAN NOT be increased in the future.

    uint256 public maxWalletSize;
    uint256 public maxTxAmount;

    uint256 public maxContractTokenBalance;
    bool inSwap = false;

    // Extras Mappings
    mapping(address => bool) public blacklist;                  /// @dev If an address is blacklisted, they cannot perform transfer() or transferFrom().
    mapping(address => bool) public whitelist;                  /// @dev Any transfer that involves a whitelisted address, will not incur a tax.
    mapping(address => uint8) public senderTaxType;             /// @dev Identifies tax type for msg.sender of transfer() call.
    mapping(address => uint8) public receiverTaxType;           /// @dev Identifies tax type for _to of transfer() call.
    mapping(uint8 => uint) public basisPointsTax;               /// @dev Mapping between taxType and basisPoints (taxed).
    mapping(address => bool) public authorized;                 /// @dev Mapping of which wallets are authorized to call specific functions.
    mapping(uint8 => uint256) public taxesAccrued;

    mapping(address => uint) public industryTokens;             /// @dev Mapping of how many locked tokens exist in a wallet (In 18 decimal format).
    mapping(address => uint) public lifetimeIndustryTokens;     /// @dev Mapping of how many locked tokens have ever been minted (In 18 decimal format).

    // -----------
    // Constructor
    // -----------

    /// @notice Initializes the TaxToken.
    /// @dev _paused - ERC20 Pausable global state variable, initial state is not paused ("unpaused").
    /// @dev The "owner" is the "admin" of this contract.
    /// @dev Initial liquidity, allocated entirely to "owner".
    /// @param  totalSupplyInput    The total supply of this token (this value is multipled by 10**decimals in constructor).
    /// @param  nameInput           The name of this token.
    /// @param  symbolInput         The symbol of this token.
    /// @param  decimalsInput       The decimal precision of this token.
    /// @param  maxWalletSizeInput  The maximum wallet size (this value is multipled by 10**decimals in constructor).
    /// @param  maxTxAmountInput    The maximum tx size (this value is multipled by 10**decimals in constructor).
    constructor(
        uint totalSupplyInput, 
        string memory nameInput, 
        string memory symbolInput, 
        uint8 decimalsInput,
        uint256 maxWalletSizeInput,
        uint256 maxTxAmountInput
    ) ERC20(nameInput, symbolInput) {
        _paused = false;
        _setupDecimals(decimalsInput);
        _totalSupply = totalSupplyInput * (10 ** decimals());

        // Create a uniswap pair for this new token.
        UNISWAP_V2_PAIR = IUniswapV2Factory(
            IUniswapV2Router02(UNIV2_ROUTER).factory()
        ).createPair(address(this), IUniswapV2Router02(UNIV2_ROUTER).WETH());
 
        senderTaxType[UNISWAP_V2_PAIR] = 1;
        receiverTaxType[UNISWAP_V2_PAIR] = 2;

        maxWalletSize = maxWalletSizeInput * (10 ** decimals());
        maxTxAmount = maxTxAmountInput * (10 ** decimals());

        maxContractTokenBalance = 1 * (10 ** decimals());

        whitelist[address(this)] = true;
        whitelist[address(0)] = true;
        whitelist[owner()] = true;

        _mint(owner(), totalSupplyInput * (10 ** decimals()));
    }

 
    // ---------
    // Modifiers
    // ---------

    /// @dev whenNotPausedUni() is used if the contract MUST be paused ("paused").
    modifier whenNotPausedUni(address a) {
        require(!paused() || whitelist[a], "TaxToken.sol::whenNotPausedUni(), Contract is currently paused.");
        _;
    }

    /// @dev whenNotPausedDual() is used if the contract MUST be paused ("paused").
    modifier whenNotPausedDual(address _from, address _to) {
        require(!paused() || whitelist[_from] || whitelist[_to], "TaxToken.sol::whenNotPausedDual(), Contract is currently paused.");
        _;
    }

    /// @dev whenNotPausedTri() is used if the contract MUST be paused ("paused").
    modifier whenNotPausedTri(address _from, address _to, address _sender) {
        require(!paused() || whitelist[_from] || whitelist[_to] || whitelist[_sender], "TaxToken.sol::whenNotPausedTri(), Contract is currently paused.");
        _;
    }

    /// @dev whenPaused() is used if the contract MUST NOT be paused ("unpaused").
    modifier whenPaused() {
        require(paused(), "TaxToken.sol::whenPaused(), Contract is not currently paused.");
        _;
    }

    /// @dev isAuthorized() is used if msg.sender MUST be either the owner, or an authorized user/contract.
    modifier onlyAuthorized {
       require(msg.sender == owner() || authorized[msg.sender] == true, "TaxToken.sol::onlyAuthorized(), msg.sender is not authorized."); 
       _;
    }

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }


    // ------
    // Events
    // ------

    /// @dev Emitted when the pause is triggered by `account`.
    event Paused(address);

    /// @dev Emitted when the pause is lifted by `account`.
    event Unpaused(address);

    /// @dev Emitted during transferFrom().
    event TransferTax(address indexed _treasury, uint256 _value);

    /// @dev Emitted when updating authorized addresses (users or contracts).
    event UpdatedAuthorizedWallets(address indexed _account, bool _state);

    event TreasuryUpdated(address, address);

    event VestingUpdated(address, address);

    event DepositorUpdated(address, address);

    event TaxesPermanentlyRemoved();

    event MaxTxUpdated(uint256);

    event MaxWalletUpdated(uint256);


    // ---------
    // Functions
    // ---------
 
    // ~ ERC20 _transfer() ~

    function _transfer(address _from, address _to, uint256 _amount) internal override {

        // taxType 0 => Xfer Tax
        // taxType 1 => Buy Tax
        // taxType 2 => Sell Tax
        uint8 _taxType;

        require(!paused() || whitelist[_from] || whitelist[_to] || whitelist[msg.sender], "TaxToken.sol::_transfer() contract is currently paused.");
        require(balanceOf(_from) >= _amount, "TaxToken::_transfer() insufficient balance");
        require(_amount > 0, "TaxToken::_transfer() amount must be greater than 0");

        // Take a tax from them if neither party is whitelisted.
        if (!whitelist[_to] && !whitelist[_from] && !whitelist[msg.sender] && _from != address(this)) {

            require (maxTxAmount >= _amount, "TaxToken::_transfer() amount exceeds maxTxAmount");
            require (!blacklist[_from], "TaxToken::_transfer() sender is blacklisted");
            require (!blacklist[_to], "TaxToken::_transfer() receiver is blacklisted");

            // Determine, if not the default 0, tax type of transfer.
            if (senderTaxType[_from] != 0) {
                _taxType = senderTaxType[_from]; // buy -> 1
            }

            if (receiverTaxType[_to] != 0) {
                _taxType = receiverTaxType[_to]; // sell -> 2
            }

            uint _taxAmt = _amount * basisPointsTax[_taxType] / 10000;
            uint _sendAmt = _amount - _taxAmt;

            require(_taxAmt + _sendAmt == _amount, "TaxToken::_transfer() critical math error");

            /// @dev if it's a sell (_taxType == 2), _to will be pair address thus we don't want to check for maxWalletSize.
            if (_taxType != 2 && _to != depositor) {
                require(balanceOf(_to) + _sendAmt <= maxWalletSize, "TaxToken::_transfer() amount exceeds maxWalletAmount");
            }

            if (_taxType == 2 && !inSwap) {
                uint256 contractTokenBalance = getContractTokenBalance();

                if(contractTokenBalance > maxTxAmount) {
                    contractTokenBalance = maxTxAmount;
                }

                if (contractTokenBalance >= maxContractTokenBalance) {
                    handleRoyalties(contractTokenBalance);
                }
            }

            super._transfer(_from, _to, _sendAmt);

            //taxesAccrued[_taxType] += _taxAmt;
            super._transfer(_from, address(this), _taxAmt);
        }
        // Skip taxation if either party is whitelisted (_from or _to).
        else {
            super._transfer(_from, _to, _amount);
        }
    }

    function handleRoyalties(uint256 _contractTokenBalance) internal lockTheSwap {
        uint256 amountWeth = swapTokensForWeth(_contractTokenBalance);

        if (amountWeth > 0) {
            // Update Treasury Accounting
            ITreasury(treasury).updateTaxesAccrued(amountWeth);
            emit TransferTax(treasury, amountWeth);
        }
    }

    function swapTokensForWeth(uint256 _amountTokensForSwap) internal returns (uint256){
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IUniswapV2Router02(UNIV2_ROUTER).WETH();

        _approve(address(this), address(UNIV2_ROUTER), _amountTokensForSwap);

        uint256[] memory amounts = IUniswapV2Router02(UNIV2_ROUTER).getAmountsOut(
            _amountTokensForSwap, 
            path
        );

        // make the swap
        IUniswapV2Router02(UNIV2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountTokensForSwap,
            0,
            path,
            address(treasury),
            block.timestamp + 300
        );

        return amounts[1];
    }


    // ~ ERC20 Pausable ~

    /// @notice Pause the contract, blocks transfer() and transferFrom().
    /// @dev    Contract MUST NOT be paused to call this, caller must be "owner".
    function pause() external onlyOwner whenNotPausedUni(msg.sender) {
        _paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the contract.
    /// @dev    Contract MUST be paused to call this, caller must be "owner".
    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /// @return _paused Indicates whether the contract is paused (true) or not paused (false).
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    
    // ~ TaxType & Fee Management ~
    
    /// @notice     Used to store the LP Pair to differ type of transaction. Will be used to mark a BUY.
    /// @dev        _taxType must be lower than 3 because there can only be 3 tax types; buy, sell, & send.
    /// @param      _sender This value is the PAIR address.
    /// @param      _taxType This value must be be 0, 1, or 2. Best to correspond value with the BUY tax type.
    function updateSenderTaxType(address _sender, uint8 _taxType) external onlyOwner {
        require(_taxType < 3, "TaxToken::updateSenderTaxType(), _taxType must be less than 3.");
        senderTaxType[_sender] = _taxType;
    }

    /// @notice     Used to store the LP Pair to differ type of transaction. Will be used to mark a SELL.
    /// @dev        _taxType must be lower than 3 because there can only be 3 tax types; buy, sell, & send.
    /// @param      _receiver This value is the PAIR address.
    /// @param      _taxType This value must be be 0, 1, or 2. Best to correspond value with the SELL tax type.
    function updateReceiverTaxType(address _receiver, uint8 _taxType) external onlyOwner {
        require(_taxType < 3, "TaxToken::updateReceiverTaxType(), _taxType must be less than 3.");
        receiverTaxType[_receiver] = _taxType;
    }

    /// @notice     Used to map the tax type 0, 1 or 2 with it's corresponding tax percentage.
    /// @dev        Must be lower than 2000 which is equivalent to 20%.
    /// @param      _taxType This value is the tax type. Has to be 0, 1, or 2.
    /// @param      _bpt This is the corresponding percentage that is taken for royalties. 1200 = 12%.
    function adjustBasisPointsTax(uint8 _taxType, uint _bpt) external onlyOwner {
        require(_bpt <= 2000, "TaxToken.sol::adjustBasisPointsTax(), _bpt > 2000 (20%).");
        require(!taxesRemoved, "TaxToken.sol::adjustBasisPointsTax(), Taxation has been removed.");
        basisPointsTax[_taxType] = _bpt;
    }

    /// @notice Permanently remove taxes from this contract.
    /// @dev    An input is required here for sanity-check, given importance of this function call (and irreversible nature).
    /// @param  _key This value MUST equal 42 for function to execute.
    function permanentlyRemoveTaxes(uint _key) external onlyOwner {
        require(_key == 42, "TaxToken::permanentlyRemoveTaxes(), _key != 42.");
        require(!taxesRemoved, "TaxToken.sol::adjustBasisPointsTax(), Taxation has already been removed.");
        basisPointsTax[0] = 0;
        basisPointsTax[1] = 0;
        basisPointsTax[2] = 0;
        taxesRemoved = true;

        emit TaxesPermanentlyRemoved();
    }


    // ~ Admin ~

    function transferOwnership(address newOwner) public override onlyOwner {
        whitelist[newOwner] = true;
        super.transferOwnership(newOwner);
    }

    function distributeRoyaltiesToTreasury() external onlyOwner {
        // TODO: Add require statement
        if (!inSwap) {
            handleRoyalties(getContractTokenBalance());
        }
        // test contractTokenbalance being over max Tx amount
    }

    /// @notice This is used to change the owner's wallet address. Used to give ownership to another wallet.
    /// @param  _account is the address that will change from authorized or not.
    /// @param  _state (True or False) If true, _account is authorized, if false, _account is not authorized.
    function updateAuthorizedList(address _account, bool _state) external onlyOwner {
        require(_account != address(0), "TaxToken.sol::updateAuthorizedList() _owner == 0");
        require(authorized[_account] == _state, "TaxToken.sol::updateAuthorizedList() _account is already set to _state");

        authorized[_account] = _state;

        emit UpdatedAuthorizedWallets(_account, _state);
    }

    /// @notice Set the treasury (contract) which receives taxes generated through transfer() and transferFrom().
    /// @param  _treasury is the contract address of the treasury.
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != treasury, "TaxToken.sol::setTreasury() already set to treasury address");
        require(_treasury != address(0), "TaxToken.sol::setTreasury() treasury cannot be address(0)");

        treasury = _treasury;
        modifyWhitelist(treasury, true);

        emit TreasuryUpdated(treasury, _treasury);
    }

    /// @notice Set the vesting (contract) which is then whitelisted and minted the amount needed for vesting.
    /// @param  _vesting is the contract address of the vesting.
    function setVesting(address _vesting) external onlyOwner {
        require(_vesting != vesting, "TaxToken.sol::setVesting() already set to treasury address");
        require(_vesting != address(0), "TaxToken.sol::setVesting() treasury cannot be address(0)");

        vesting = _vesting;
        modifyWhitelist(vesting, true);

        uint256 amount = IVesting(vesting).getAllVestedTokens();
        _mint(vesting, amount);

        emit VestingUpdated(vesting, _vesting);
    }

    /// @notice Set the depositor (contract) which is the backend contract for the dapp.
    /// @param  _depositor is the contract address of the depositor contract.
    function setDepositor(address _depositor) external onlyOwner {
        require(_depositor != depositor, "TaxToken.sol::setdepositor() already set to treasury address");
        require(_depositor != address(0), "TaxToken.sol::setdepositor() treasury cannot be address(0)");

        depositor = _depositor;
        modifyWhitelist(depositor, false); /// @dev Depositor should not be whitelisted.

        emit DepositorUpdated(depositor, _depositor);
    }

    /// @notice Updates the maxContractTokebBalance var which is used to set the distribution threshhold of royalties to the Treasury.
    /// @param  _amount is the amount of tokens that need to be hit to distribute.
    function updateMaxContractTokenBalance(uint256 _amount) external onlyOwner {
        maxContractTokenBalance = (_amount * 10 ** decimals());
    }

    /// @notice Adjust maxTxAmount value (maximum amount transferrable in a single transaction).
    /// @dev    Does not affect whitelisted wallets.
    /// @param  _maxTxAmount is the max amount of tokens that can be transacted at one time for a non-whitelisted wallet.
    function updateMaxTxAmount(uint256 _maxTxAmount) external onlyOwner {
        require(_maxTxAmount > 0, "TaxToken.sol::updateMaxTxAmount() _maxTxAmount must be gt 0");

        maxTxAmount = (_maxTxAmount * 10 ** decimals());

        emit MaxTxUpdated(maxTxAmount);
    }

    /// @notice This function is used to set the max amount of tokens a wallet can hold.
    /// @dev    Does not affect whitelisted wallets.
    /// @param  _maxWalletSize is the max amount of tokens that can be held on a non-whitelisted wallet.
    function updateMaxWalletSize(uint256 _maxWalletSize) external onlyOwner {
        require(_maxWalletSize > 0, "TaxToken.sol::updateMaxWalletSize() _maxWalletSize must be gt 0");

        maxWalletSize = (_maxWalletSize * 10 ** decimals());

        emit MaxWalletUpdated(maxWalletSize);
    }

    /// @notice This function is used to add wallets to the whitelist mapping.
    /// @dev    Whitelisted wallets are not affected by maxWalletSize, maxTxAmount, or taxes.
    /// @param  _wallet is the wallet address that will have their whitelist status modified.
    /// @param  _whitelisted use True to whitelist a wallet, otherwise use False to remove wallet from whitelist.
    function modifyWhitelist(address _wallet, bool _whitelisted) public onlyOwner {
        whitelist[_wallet] = _whitelisted;
    }

    /// @notice This function is used to add or remove wallets from the blacklist.
    /// @dev    Blacklisted wallets cannot perform transfer() or transferFrom().
    ///         unless it's to or from a whitelisted wallet.
    /// @param  _wallet is the wallet address that will have their blacklist status modified.
    /// @param  _blacklist use True to blacklist a wallet, otherwise use False to remove wallet from blacklist.
    function modifyBlacklist(address _wallet, bool _blacklist) external onlyOwner {
        if (_blacklist) {
            require(!whitelist[_wallet], "TaxToken.sol::modifyBlacklist(), cannot blacklist a whitelisted wallet");
            require(_wallet != treasury, "TaxToken.sol::modifyBlacklist(), cannot blacklist treasury");
            require(_wallet != depositor, "TaxToken.sol::modifyBlacklist(), cannot blacklist depositor");
            require(_wallet != vesting, "TaxToken.sol::modifyBlacklist(), cannot blacklist vesting");
            require(_wallet != UNIV2_ROUTER, "TaxToken.sol::modifyBlacklist(), cannot blacklist the Uniswap ROUTER");
            require(_wallet != UNISWAP_V2_PAIR, "TaxToken.sol::modifyBlacklist(), cannot blacklist the Uniswap PAIR");
            require(_wallet != address(this), "TaxToken.sol::modifyBlacklist(), cannot blacklist this contract");
        }
        blacklist[_wallet] = _blacklist;
    }
    
    /// @notice This function will create new tokens and adding them to total supply.
    /// @dev    Does not truncate so amount needs to include the 18 decimal points.
    ///         Needed too add new tokens to supply if we want to get listed on multiple exchanges.
    /// @param  _wallet the account we're minting tokens to.
    /// @param  _amount the amount of tokens we're minting.
    function mint(address _wallet, uint256 _amount) public onlyAuthorized() {
        _mint(_wallet, _amount);
    }

    /// @notice This function will destroy existing tokens and deduct them from total supply.
    /// @dev    Does not truncate so amount needs to include the 18 decimal points.
    /// @param  _wallet the account we're burning tokens from.
    /// @param  _amount the amount of tokens we're burning.
    function burn(address _wallet, uint256 _amount) public onlyAuthorized() {
        _burn(_wallet, _amount);
    }

    /// @notice This function is used to mint tokens and log their creation to the industry wallet mappings.
    /// @dev    Any tokens minted through this process can only be used inside of the NFT marketplace to mint new NFTS (can only be burned).
    /// @dev    Users may still buy and sell new or prior existing non-minted tokens but these will be soulbound. 
    /// @dev    Does not truncate so amount needs to include the 18 decimal points.
    /// @param  _wallet is the wallet address that will recieve these minted tokens.
    /// @param  _amount is the amount of tokens to be minted into _wallet.
    function industryMint(address _wallet, uint256 _amount) external onlyAuthorized {
        _mint(_wallet, _amount);

        industryTokens[_wallet] += _amount;
        lifetimeIndustryTokens[_wallet] += _amount;
    }

    /// @notice This function will destroy existing tokens and deduct them from total supply.
    /// @dev    Does not truncate so amount needs to include the 18 decimal points.    
    /// @param  _wallet the account we're burning tokens from.
    /// @param  _amount the amount of tokens we're burning.
    function industryBurn(address _wallet, uint256 _amount) external onlyAuthorized {
        require(_wallet != address(0), "TaxToken.sol::industryBurn(), Cannot burn to zero address.");
        require(balanceOf(_wallet) >= _amount, "TaxToken.sol::industryBurn(), Insufficient balance of $PROVE to burn.");

        if (industryTokens[_wallet] >= _amount) {
            _burn(_wallet, _amount);
            industryTokens[_wallet] -= _amount;
        } else {
            _burn(_wallet, _amount);
            industryTokens[_wallet] = 0;
        }
    }


    // ~ Read ~

    /// @notice This functions returns the number of taxToken are inside the contract.
    /// NOTE:   These tokens have most likely been accrued from taxes.
    /// @return uint256 the num of tokens stored in this contract.
    function getContractTokenBalance() view public returns (uint256) {
        return balanceOf(address(this));
    }

    /// @notice This function is a VIEW function that returns the amount of industry tokens,
    ///         full balance, and normal tokens a wallet has.
    /// @dev    This function is for the front end to pull industry data for a specific wallet.
    /// @return numTokens the amount of taxTokens the _wallet holds.
    /// @return numIndustryTokens the amount of tokens they hold that is industry tokens.
    /// @return numDifference the amount of tokens they have that are NOT industry tokens.
    /// @return lifetime the amount of industry tokens that have been minted to _wallet in total.
    function getIndustryTokens(address _wallet) external view returns (uint numTokens, uint numIndustryTokens, uint numDifference, uint lifetime) {
        uint fullBalance = IERC20(address(this)).balanceOf(_wallet);
        uint industryBalance = industryTokens[_wallet];
        uint difference = fullBalance - industryBalance;

        // TODO: Test logic here -> fullbalalance - industryBalance might cause negative number -> underflow

        return (fullBalance, industryBalance, difference, lifetimeIndustryTokens[_wallet]);
    }
}