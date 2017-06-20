pragma solidity ^0.4.11;
import "./StandardToken.sol";
import "./SafeMath.sol";

//Simple eth->token contract borrowed from BAT.
//Allows for bonuses during different phases.
//Gives devs a cut of eth and tokens.
//Pays out rewards daily. Rewards pay for themselves based on the gas price.
contract MASSToken is StandardToken, SafeMath {

    // metadata
    string public constant name = "MASS";
    string public constant symbol = "MASS";
    uint256 public constant decimals = 18;
    string public version = "1.0";

    // contracts
    address public contractOwner;
    address public ethFundDeposit;  // deposit address for ETH for MASS Ltd. Investment/Contract
    address public ethFeeDeposit;   // deposit address for ETH for MASS Ltd. token fees
    address public massPromisoryDeposit; // deposit address for MASS to prior commitments.
    address public ethPromisoryDeposit; // deposit address for Eth for prior commitments.
    address public massBountyDeposit; // deposit address for MASS to bounty programs.
    address public ethBountyDeposit; // deposit address for Eth to bounty programs.

    // crowdsale parameters
    bool public isFinalized = false;              // switched to true in operational state
    uint256 public fundingStartBlock = 0;
    uint256 public fundingEndBlock = 0;
    uint256 public constant tokenExchangeRate = 1000; // 1000 MASS (attograms) tokens per 1 ETH (wei)
    uint256 public constant tokenCreationCap =  61 * (10**6) * 10**decimals; // 61m MASS cap
    mapping (address => uint256) blockRewards; // Map block rewards to the remote Ethereum addresses.
    mapping (address => uint256) bonuses; // Map rewards to be paid out to the addresses.
    mapping (address => uint256) totalRewards; // Map total rewards earned for the addresses.
    uint256 public totalEthereum = 0; // Hold the total value of Ethereum of the entire pool, used to calculate cashout/burn.
    uint256 public totalPreSale = 0; // Store the number of tokens sold during presale.
    
    // presale/ICO bonues
    bool public presaleReleased = false;
    uint256 public constant massFee = 10; // 10%
    uint256 public constant promisoryFee = 100;  // 1%
    uint256 public constant icoSaleBonus20 = 200; // 20% more tokens for first 5m tokens on ICO
    uint256 public constant icoSaleBonus20Cap = 5 * (10**6) * 10**decimals;
    uint256 public constant icoSaleBonus10 = 100; // 10% more tokens for next 10m tokens on ICO
    uint256 public constant icoSaleBonus10Cap = 15 * (10**6) * 10**decimals;

    // events
    event LogRefund(address indexed _to, uint256 _value);
    event CreateMASS(address indexed _to, uint256 _value);
    event UpdatedRewards(address indexed _to, uint256 _value);
    event RewardSent(address indexed _to, uint256 _value);
    event BlockRewarded(address indexed _remote, uint256 _value);
    
    // constructor
    function MASSToken(
        address _ethFundDeposit,
        address _massFundDeposit,
        address _ethFeeDeposit,
        address _massPromisoryDeposit,
        address _ethPromisoryDeposit,
        address _massBountyDeposit,
        address _ethBountyDeposit,
        uint256 _fundingStartBlock,
        uint256 _fundingEndBlock)
    {
      isFinalized = false;                   //controls pre through crowdsale state
      ethFundDeposit = _ethFundDeposit;
      ethFeeDeposit = _ethFeeDeposit;
      massFundDeposit = _massFundDeposit;
      massPromisoryDeposit = _massPromisoryDeposit;
      ethPromisoryDeposit = _ethPromisoryDeposit;
      massBountyDeposit = _massBountyDeposit;
      ethBountyDeposit = _ethBountyDeposit;
      fundingStartBlock = _fundingStartBlock;
      fundingEndBlock = _fundingEndBlock;
      totalSupply = 0;
      allowTransfers = false; // No transfers during ico.
      saleStart = now;
      contractOwner = msg.sender;
      // Baked in presale accounts.
      releasePreSaleTokens();
    }
    
    function releasePreSaleTokens() internal {
        if (presaleReleased) throw;
        balances[0x422c18FD8aeb1Ad77200190c6355C79B1086Fcc2] = 1300 * (10**18);
        bonuses[0x422c18FD8aeb1Ad77200190c6355C79B1086Fcc2] = 300 * (10**18); // Store the bonus.
        balances[massFundDeposit] = 1300 * (10**17); // 10% goes to MASS Ltd.
        balances[massPromisoryDeposit] = 1300 * (10**16); // 1% goes to prior commitments.
        balances[massBountyDeposit] = 1300 * (10**16); // 1% goes to bounty programs.
        totalSupply += balances[0x422c18FD8aeb1Ad77200190c6355C79B1086Fcc2] + balances[massFundDeposit] + balances[massPromisoryDeposit] + balances[massBountyDeposit];
        totalPreSale += totalSupply;
        CreateMASS(0x422c18FD8aeb1Ad77200190c6355C79B1086Fcc2, balances[0x422c18FD8aeb1Ad77200190c6355C79B1086Fcc2]);
        //balances[address2] = 1003 * (10**18);
        //bonuses[address2] = 300 * (10**18); // Store the bonus.
        //balances[massFundDeposit] += 1003 * (10**17); // 10% goes to MASS Ltd.
        //balances[massPromisoryDeposit] = 1003 * (10**16); // 1% goes to prior commitments.
        //balances[massBountyDeposit] = 1003 * (10**16); // 1% goes to bounty programs.
        //totalSupply += balances[address2] + balances[massFundDeposit] + balances[massPromisoryDeposit] + balances[massBountyDeposit];
        //totalPreSale += totalSupply;
        //CreateMASS(address2, balances[address2]);
        presaleReleased = true;
    }

    /// @dev Update entire pool's worth whenever we get a unstaked block rewards.
    function updateTotalEthereumBalance(uint256 _amount) {
        require (msg.sender == contractOwner);
        totalEthereum += _amount;
    }
    
    /// @dev Set the ICO funding period once presale is over.
    function setFundingPeriod(uint256 _fundingStartBlock, uint256 _fundingEndBlock) {
        require (msg.sender == contractOwner);
        fundingStartBlock = _fundingStartBlock;
        fundingEndBlock = _fundingEndBlock;
        //totalPreSale = totalSupply;
    }
    
    /// @dev The backend sets the amount of rewards per address.
    function setRewards(address _to, uint256 _value) {
        require (msg.sender == contractOwner);
        rewards[_to] += _value;
        totalRewards[_to] += _value;
        UpdatedRewards(_to, _value);
    }
    
    // @all Allow token holders to see how much they've been rewarded over their lifetime.
    function getRewards() constant returns (uint256 amount) {
        return totalRewards[msg.sender];
    }
    
    /// @dev Mark the reward as sent and decrease it from the balance. Rewards are sent out of contract to save on gas.
    function sentReward(address _to, uint256 _value) {
        require (msg.sender == contractOwner);
        rewards[_to] -= _value;
        RewardSent(_to, _value);
    }
    
    /// @dev Increase and decrease block rewards paid out to our remote wallets.
    function updateBlockRewards(address _remote, uint256 _value) {
        require (msg.sender == contractOwner);
        blockRewards[_remote] += _value;
        BlockRewarded(_remote, _value);
    }
    
    /// @dev Allow MASS Ltd. to release vested MASS tokens after 1 year.
    function releaseVestedMASS() {
        require (msg.sender == contractOwner);
        if (now >= saleStart + (365 days)) {
            releaseFunds = true;
        }
    }

    /// Accepts ether and creates new MASS tokens.
    function createTokens() payable external {
      if (isFinalized) throw;
      require(!isContract(msg.sender)); //Disallow contracts from purchasing.
      if (block.number < fundingStartBlock) throw;
      if (block.number > fundingEndBlock) throw;
      if (msg.value == 0) throw;
      
      // Check if we've sold out completely.
      if (totalSupply == tokenCreationCap) throw; // Don't allow purchases above cap.
      
      //Handle ico bonuses
      uint256 tmpExchangeRate = 0;
      uint256 bonusTokens = 0;
      uint256 tmpTotalSupply = totalSupply;
      tmpTotalSupply = totalSupply - totalPreSale;
      if (tmpTotalSupply < icoSaleBonus20Cap) {
          bonusTokens = (icoSaleBonus20 * msg.value);
          tmpExchangeRate = tokenExchangeRate + icoSaleBonus20;
      } else if (tmpTotalSupply < icoSaleBonus10Cap) {
          bonusTokens = (icoSaleBonus10 * msg.value);
          tmpExchangeRate = tokenExchangeRate + icoSaleBonus10;
      }
      
      if (tokenExchangeRate > tmpExchangeRate) {
        uint256 tokens = safeMult(msg.value, tokenExchangeRate); // check that we're not over totals
      } else {
        tokens = safeMult(msg.value, tmpExchangeRate); // check that we're not over totals
      }
      
      //MASS Ltd. takes 10% on top of purchases.
      uint256 massFeeTokens = (tokens/massFee);
      uint256 promisoryFeeTokens = (tokens/promisoryFee);
      uint256 bountyFeeTokens = (tokens/promisoryFee);
      uint256 totalTokens = tokens + massFeeTokens + promisoryFeeTokens + bountyFeeTokens;
      uint256 checkedSupply = safeAdd(totalSupply, totalTokens);

      // return money if something goes wrong
      if (tokenCreationCap < checkedSupply) throw;  // odd fractions won't be found

      totalSupply = checkedSupply;
      balances[msg.sender] += tokens;  // safeAdd not needed; bad semantics to use here
      balances[massFundDeposit] += massFeeTokens; //Add the fee to the MASS address.
      balances[massPromisoryDeposit] += promisoryFeeTokens; // Add the fee to the prior commitments address.
      balances[massBountyDeposit] += bountyFeeTokens; // Add the fee to the bounty programs.
      bonuses[msg.sender] += bonusTokens;
      CreateMASS(msg.sender, tokens);  // logs token creation
    }

    /// @dev Ends the funding period and sends the ETH home
    function finalize() external {
      if (isFinalized) throw;
      require (msg.sender == contractOwner); // locks finalize to the ultimate ETH owner
      if(block.number <= fundingEndBlock && totalSupply != tokenCreationCap) throw;
      // move to operational
      isFinalized = true;
      uint256 poolBalance = this.balance; // Store the eth balance of the entire pool.
      uint256 feeBalance = (poolBalance/massFee);
      uint256 bountyBalance = (poolBalance/promisoryFee); // 1% to Bounty
      uint256 promisoryBalance = (poolBalance/promisoryFee); // 1% to prior commitments.
      poolBalance -= feeBalance; //Subtract the 10% fee from the investment pool and send to MASS Ltd.
      poolBalance -= bountyBalance;
      poolBalance -= promisoryBalance;
      totalEthereum = poolBalance; // Store the final value of Ethereum before it is sent.
      if(!ethFundDeposit.send(poolBalance)) throw;  // send 88% of the eth to the fund.
      if(!ethFeeDeposit.send(feeBalance)) throw;  // send 10% eth to MASS Ltd.
      if(!ethBountyDeposit.send(bountyBalance)) throw; // send 1% eth to the bounty address
      if(!ethPromisoryDeposit.send(promisoryBalance)) throw; // send 1% eth to the promisory address for prior commitments.
    }
    
    /// @dev Disable transfers of MASS during payouts.
    function disableTransfers() {
        if (!isFinalized) throw;
        require (msg.sender == contractOwner);
        allowTransfers = false;
    }
    
    /// @dev Allow transfers after MASS payouts.
    function enableTransfers() {
        if (!isFinalized) throw;
        require (msg.sender == contractOwner);
        allowTransfers = true;
    }

    /// @dev Change ownership of contract in case of emergency.
    function changeOwnership(address newOwner) {
        require (msg.sender == contractOwner);
        contractOwner = newOwner;
    }

    /// @dev Internal function to prevent contracts from purchasing tokens.
     // Borrowed from StatusContributions.sol (SNT)
    function isContract(address _address) constant internal returns (bool) {
        if (_address == 0) return false;
        uint256 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}
