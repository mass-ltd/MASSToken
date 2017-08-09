pragma solidity ^0.4.11;

import "./SafeMath.sol";

//This contract will handle the following:
// Point of contact between Ethereum funds and exchanges
// Publish outgoing eth addresses with a waiting period of 1 week before they can be sent eth.
// Publish PoS/Masternode wallet addresses
// Publish exchange wallet addresses
// Force transactions over 30% of the entire pool to wait for 1 week before sending.
// List new and currently supported coins
// Track rebalancing of distributed assets.
// Track "unicorn" rebalancing (200% return gives all token holders, including MASS Cloud Ltd, a share of 10% of the return)
// Prevent transactions to unapproved addresses
// Kill switch - liquidate all assets and send to token holders, effectively ending MASSTokens

// Token subcontract function reference.
contract Token {
  uint256 public _totalSupply;
  function balanceOf(address _owner) constant returns (uint256 balance);
}

contract MASSContract {
    using SafeMath for uint256;
    
    address public MASSToken; // Address of the main MASSToken contract
    address public MASSContract = 0; // Address of the next iteration of this contract, if there is one, otherwise empty.
    address public contractOwner; // Set an address to own the contract and control the functions within.
    address public rewardsAddress; // The address of the wallet used to send rewards.
    bool public isLiquidated = false; // Is MASS over?
    bool hasICOEth = false;
    uint256 public totalEthereum = 0; // Keep track of the value of the pool.    

    // Address mappings.
    mapping (string => string) stakedWallets; //Map wallet names to addresses: "neoscoin-1" => "0x0dd5...."
    
    struct Coins {
    	string name;
    	string symbol;
    	string url;
    }
    
    struct Outgoing {
        address addr;
        uint256 amount;
        bool canSend;
        uint256 startTime;
    }
    
    struct Pending {
        string name;
        address addr;
        uint256 amount;
        uint256 startTime;
        bool sent;
    }

    struct Exchanges {
        string name;
        address addr;
        uint256 amount;
        bool canSend;
        uint256 startTime;
        bool active;
    }
    
    mapping (string => Pending) pendingStaked;
    mapping (address => Pending) pendingExchanges;
    mapping (address => Exchanges) exchangeAddresses;
    // TODO:
    // add coins functionality, currently only adds (pushes) coin to array.
    Coins[] coins;
    
    // Events
    event NewExchangeAddress(string, address);
    event AllowedExchangeAddress(address);
    event UpdatedExchange(string, address, bool);
    event NewStakedWallet(string, string);
    event FundedExchange(string, address, uint256);
    event FundedStakedWallet(string, address, uint256);
    event PendingStakedWallet(string, string, uint256);
    event PendingExchange(string, address, uint256);
    event NewCoin(string, string, string);
    event Liquidate();
    
    //modifier functions
    // Only allow the contract owner to run the function.
    modifier onlyOwner() {
      require (msg.sender == contractOwner);
      _;
    }
    
    // Constructor
    function MASSContract(address _owner, address _MASSToken, address _rewards) {
      contractOwner = _owner;
      MASSToken = _MASSToken;
      rewardsAddress = _rewards;
    }
    
    // Accept eth from the ICO.
    // This can only happen once since the MASSToken contract will only send once and end.
    function () payable {
      require (msg.sender == MASSToken); // Only accept eth from the ICO contract.
      totalEthereum += msg.value;
    }

    // Increase total ethereum when rebalancing.
    function increaseTotalEthereum(uint256 _amount) public onlyOwner {
      totalEthereum = totalEthereum.add(_amount);
    }

    // Decrease total ethereum when rebalancing.
    function decreaseTotalEthereum(uint256 _amount) public onlyOwner {
      if (_amount > totalEthereum) {
        totalEthereum = 0;
      } else {
        totalEthereum = totalEthereum.sub(_amount);
      }
    }

    // Add an address for an exchange. Set the start time to the current blocktime.
    function addExchangeAddress(string _name, address _addr) public onlyOwner {
      exchangeAddresses[_addr] = Exchanges(_name, _addr, 0, false, now, true);
      NewExchangeAddress(_name, _addr);
    }

    // Allow addresses to be sendable after 1 week.
    function updateExchangeAddress(address _addr) public onlyOwner returns (bool success) {
      if (now < exchangeAddresses[_addr].startTime + (7 days)) return false;
      exchangeAddresses[_addr].canSend = true;
      AllowedExchangeAddress(_addr);
      return true;
    }

    // Allow pending transactions to exchanges to go through after 1 week.
    function updatePendingExchangeTransaction(address _addr) public onlyOwner returns (bool success) {
      if (now < pendingExchanges[_addr].startTime + (7 days)) return false;
      if (pendingExchanges[_addr].sent) return false; // Already sent.
      pendingExchanges[_addr].sent = true;
      _addr.transfer(pendingExchanges[_addr].amount);
      return true;
    }
   
    // Deactivate an exchange address.
    function removeExchangeAddress(string _name, address _addr) public onlyOwner {
      exchangeAddresses[_addr].active = false;
      UpdatedExchange(_name, _addr, false);
    }

    // Activate an exchange address that was previously deactivated. This cannot be used to bypass the waiting period.
    function activateExchangeAddress(string _name, address _addr) public onlyOwner {
      exchangeAddresses[_addr].active = true;
      UpdatedExchange(_name, _addr, true);
    }
    
    // Add the name and address of a staking wallet.
    function addStakedWallet(string _name, string _addr) public onlyOwner {
      stakedWallets[_name] = _addr;
      NewStakedWallet(_name, _addr);
    }
    
    // Prepare to send eth to an exchange.
    function fundExchange(string _name, address _addr, uint256 _amount) public onlyOwner returns (bool success){
      require(exchangeAddresses[_addr].canSend); //Can only send to approved addresses.
        
      // Calculate 30% of the pool's balance.
      uint256 maxSend = totalEthereum.mul(3);
      maxSend = maxSend.div(10);
      if (maxSend < exchangeAddresses[_addr].amount) { //Do not send more than 30%.
        pendingExchanges[_addr] = Pending(_name, _addr, _amount, now, false);
        PendingExchange(_name, _addr, _amount);
        return true;
      } else {
        _addr.transfer(_amount);
        exchangeAddresses[_addr].amount = _amount;
        FundedExchange(_name, _addr, _amount);
        return true;
      }
      return false; // This should not happen.
    }
    
    function addNewCoin(string name, string symbol, string url) public onlyOwner {
      coins.push(Coins(name, symbol, url));
      NewCoin(name, symbol, url);
    }
    
    function updateContract(address _addr) public onlyOwner {
      MASSContract = _addr;
    }
    
    function updateRewardsAddress (address _addr) public onlyOwner {
      rewardsAddress = _addr;
    }
    
    function updateOwner(address _owner) public onlyOwner {
      contractOwner = _owner;
    }
    
    function getStakedWalletFromName(string name) public constant returns (string) {
      return stakedWallets[name];
    }
    
    // This function ends MASS and marks it so every token holder gets their fair share of Eth depending on how much MASS they hold.
    function liquidateAll() public onlyOwner returns (bool success) {
      if (isLiquidated) return false;
      isLiquidated = true;
      Liquidate();
      return true;
    }
}
