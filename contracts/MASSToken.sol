pragma solidity ^0.4.11;
import "./StandardToken.sol";
import "./SafeMath.sol";

//Allows for bonuses during different phases.
//Gives devs a cut of eth and tokens.
//Initial ICO design based off BAT (known working and secure).
contract MASSToken is StandardToken {
		using SafeMath for uint256;
		
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
    uint256 public totalPreSale = 0; // Store the number of tokens sold during presale.
    
    // presale/ICO bonues
    uint256 constant massFee = 10; // 10%
    uint256 constant massFeeExchangeRate = 100; // 100 MASS per Eth is 10% of the real exchange rate.
    uint256 constant priorAndBountyExchangeRate = 10; // 10 MASS per Eth is 1% of the real exchange rate.
    uint256 constant promisoryFee = 100;  // 1%
    uint256 constant icoSaleBonus20 = 200; // 20% more tokens for first 6m (5m + 1m bonus) tokens on ICO
    uint256 constant icoSaleBonus20Cap = 6 * (10**6) * 10**decimals;
    uint256 constant icoSaleBonus10 = 100; // 10% more tokens for next 11m (10m + 1m bonus) tokens on ICO
    uint256 constant icoSaleBonus10Cap = 17 * (10**6) * 10**decimals;
    uint256 constant icoSaleBonus20EthCap = 5000 * 10**decimals; // 5k eth cap for the first 5m tokens
    uint256 constant icoSaleBonus10EthCap = 10000 * 10**decimals; // 10k eth cap for the next 10m tokens
    uint256 public icoSaleBonus20EthPool = 0; // Track the eth received for each bonus pool so we can split properly.
    uint256 public icoSaleBonus10EthPool = 0;

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
      ethFundDeposit = _ethFundDeposit;
      ethFeeDeposit = _ethFeeDeposit;
      massFundDeposit = _massFundDeposit;
      massPromisoryDeposit = _massPromisoryDeposit;
      ethPromisoryDeposit = _ethPromisoryDeposit;
      massBountyDeposit = _massBountyDeposit;
      ethBountyDeposit = _ethBountyDeposit;
      fundingStartBlock = _fundingStartBlock;
      fundingEndBlock = _fundingEndBlock;
      _totalSupply = 0;
      allowTransfers = false; // No transfers during ico.
      saleStart = now;
      contractOwner = msg.sender;
    }
    
    // We cannot bake the addresses in because there may be too many and there is too much math involved.
    // Instead, we'll have to automatically (via a script) import presale addresses and values.
    // These can be verified and checked against the presale contract.
    function releasePreSaleTokens(address _address, uint256 _amount, uint256 _bonus, uint256 _massFund, uint256 _bountyAndPriorFund) external {
        require (msg.sender == contractOwner);
        if (block.number > fundingStartBlock) throw; // Do not allow this one the ICO starts.
        balances[_address] = balances[_address].add(_amount);
        bonuses[_address] = bonuses[_address].add(_bonus);
        balances[massFundDeposit] = balances[massFundDeposit].add(_massFund); // 10% goes to MASS Cloud Ltd.
        balances[massPromisoryDeposit] = balances[massPromisoryDeposit].add(_bountyAndPriorFund); // 1% goes to prior commitments.
        balances[massBountyDeposit] = balances[massBountyDeposit].add(_bountyAndPriorFund); // 1% goes to bounty programs.
        _totalSupply = _totalSupply.add(balances[_address]);
        _totalSupply = _totalSupply.add(_massFund);
        _totalSupply = _totalSupply.add(_bountyAndPriorFund);
        _totalSupply = _totalSupply.add(_bountyAndPriorFund); // Twice, once for bounty and once for prior commitments.
        totalPreSale = _totalSupply; // Set the total presale to the total supply, overwriting it each iteration as the final value will always be correct.
        CreateMASS(_address, balances[_address]);
    }

    // Allow the contract owner to add the funds from the presale without buying tokens.
    function addPreSaleFunds() payable external {
        require (msg.sender == contractOwner);
        if (isFinalized) throw;
    }

    /// @dev Increase entire pool's worth whenever we get a unstaked block rewards.
    function increaseTotalEthereumBalance(uint256 _amount) {
        require (msg.sender == contractOwner);
        totalEthereum = totalEthereum.add(_amount);
    }

    /// @dev Decrease entire pool's worth whenever we burn.
    function decreaseTotalEthereumBalance(uint256 _amount) {
        require (msg.sender == contractOwner);
        if (_amount <= totalEthereum) {
          totalEthereum = totalEthereum.sub(_amount);
        } else {
          totalEthereum = 0;
        }
    }
    
    /// @dev Set the ICO funding period once presale is over.
    function setFundingPeriod(uint256 _fundingStartBlock, uint256 _fundingEndBlock) {
        require (msg.sender == contractOwner);
        fundingStartBlock = _fundingStartBlock;
        fundingEndBlock = _fundingEndBlock;
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
    
    // Accept eth for burns, do nothing else.
    function addEth() payable external {
      if (!isFinalized) throw;
      totalEthereum += msg.value;
    }
    
    // Sends eth to ethFundAddress.
    function sendEth(uint256 _value) external {
      if (!isFinalized) throw;
      require (msg.sender == contractOwner);
      if(!ethFundDeposit.send(_value)) throw;
    }

    /// Accepts ether and creates new MASS tokens.
    function () payable external {
      if (isFinalized) throw;
      require(!isContract(msg.sender)); //Disallow contracts from purchasing.
      if (block.number < fundingStartBlock) throw;
      if (block.number > fundingEndBlock) throw;
      if (msg.value == 0) throw;
      
      // Check if we've sold out completely.
      if (_totalSupply == tokenCreationCap) throw; // Don't allow purchases above cap.
      
      //Handle ico bonuses
      uint256 tmpExchangeRate = 0;
      uint256 bonusTokens = 0;
      uint256 tokens = 0;
      // Variables used to split the bonus properly.
      uint256 icoSaleEthTotal = 0;
      uint256 bonusRemainder = 0;
      uint256 mainBonus = 0;
      uint256 bonus10Tokens = 0;
      uint256 nonBonusTokens = 0;
      if (icoSaleBonus20EthPool < icoSaleBonus20EthCap) { // 20% bonus.
        icoSaleEthTotal = msg.value.add(icoSaleBonus20EthPool);
        if (icoSaleEthTotal <= icoSaleBonus20EthCap) { // Track bonuses based on eth, not total tokens.
          bonusTokens = icoSaleBonus20.mul(msg.value);
          tmpExchangeRate = tokenExchangeRate.add(icoSaleBonus20);
          tokens = msg.value.mul(tmpExchangeRate);
          icoSaleBonus20EthPool = icoSaleEthTotal; // Add the eth to the bonus pool total.
        } else { // Split the bonus.
          icoSaleBonus20EthPool = icoSaleBonus20EthCap; // Set the pool to the cap.
          bonusRemainder = icoSaleEthTotal.sub(icoSaleBonus20EthCap); // Get the difference.
          mainBonus = msg.value.sub(bonusRemainder); // Subtract the remainder from the value sent.
          bonusTokens = icoSaleBonus20.mul(mainBonus);
          tmpExchangeRate = tokenExchangeRate.add(icoSaleBonus20);
          tokens = mainBonus.mul(tmpExchangeRate); // Get their 20% bonus.
          // This can only happen once, so we know the remainder is getting the 10% bonus.
          icoSaleBonus10EthPool = icoSaleBonus10EthPool.add(bonusRemainder); // add the remainder to the 10% bonus pool.
          bonus10Tokens = icoSaleBonus10.mul(bonusRemainder);
          bonusTokens = bonusTokens.add(bonus10Tokens);
          tmpExchangeRate = tokenExchangeRate.add(icoSaleBonus10);
          bonus10Tokens = bonusRemainder.mul(tmpExchangeRate);
          tokens = tokens.add(bonus10Tokens);
        }
      } else if (icoSaleBonus10EthPool < icoSaleBonus10EthCap) { // 10% bonus
        icoSaleEthTotal = msg.value.add(icoSaleBonus10EthPool);
        if (icoSaleEthTotal <= icoSaleBonus10EthCap) {
          bonusTokens = icoSaleBonus10.mul(msg.value);
          tmpExchangeRate = tokenExchangeRate.add(icoSaleBonus10);
          tokens = msg.value.mul(tmpExchangeRate);
          icoSaleBonus10EthPool = icoSaleEthTotal; // Add the eth to the pool.
        } else { // Split the bonus
          icoSaleBonus10EthPool = icoSaleBonus10EthCap; // Set the pool to the cap.
          bonusRemainder = icoSaleEthTotal.sub(icoSaleBonus10EthCap); // Get the difference.
          mainBonus = msg.value.sub(bonusRemainder); // Subtract the remainder from the value sent.
          bonusTokens = icoSaleBonus10.mul(mainBonus);
          tmpExchangeRate = tokenExchangeRate.add(icoSaleBonus10);
          tokens = mainBonus.mul(tmpExchangeRate); // Get their 10% bonus.
          // This can only happen once, so we know the remainder is getting no bonus.
          nonBonusTokens = bonusRemainder.mul(tokenExchangeRate);
          tokens = tokens.add(nonBonusTokens);
        }
      } else { // No bonus
        tokens = msg.value.mul(tokenExchangeRate);
      }
      
      //MASS Ltd. takes 10% on top of purchases.
      uint256 massFeeTokens = msg.value.mul(massFeeExchangeRate); // 10% of the purchased tokens go to MASS Cloud Ltd.
      uint256 promisoryFeeTokens = msg.value.mul(priorAndBountyExchangeRate); // 1% of the purchased tokens go to prior commitments.
      uint256 bountyFeeTokens = msg.value.mul(priorAndBountyExchangeRate); // 1% of the purchased tokens go to bounty programs.
      uint256 totalTokens = tokens.add(massFeeTokens);
      totalTokens = totalTokens.add(promisoryFeeTokens);
      totalTokens = totalTokens.add(bountyFeeTokens);
      uint256 checkedSupply = _totalSupply.add(totalTokens);

      // return money if something goes wrong
      if (tokenCreationCap < checkedSupply) throw;  // odd fractions won't be found

      _totalSupply = checkedSupply;
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
      if(block.number <= fundingEndBlock && _totalSupply != tokenCreationCap) throw;
      // move to operational
      isFinalized = true;
      uint256 poolBalance = this.balance; // Store the eth balance of the entire pool.
      uint256 feeBalance = poolBalance.div(massFee);
      uint256 bountyBalance = poolBalance.div(promisoryFee); // 1% to Bounty
      uint256 promisoryBalance = poolBalance.div(promisoryFee); // 1% to prior commitments.
      poolBalance -= feeBalance; //Subtract the 10% fee from the investment pool and send to MASS Ltd.
      poolBalance -= bountyBalance;
      poolBalance -= promisoryBalance;
      totalEthereum = poolBalance; // Store the final value of Ethereum before it is sent.
      allowTransfers = true;
      if(!ethFundDeposit.send(poolBalance)) throw;  // send 88% of the eth to the fund.
      if(!ethFeeDeposit.send(feeBalance)) throw;  // send 10% eth to MASS Ltd.
      if(!ethBountyDeposit.send(bountyBalance)) throw; // send 1% eth to the bounty address
      if(!ethPromisoryDeposit.send(promisoryBalance)) throw; // send 1% eth to the promisory address for prior commitments.
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
