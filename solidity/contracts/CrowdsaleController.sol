pragma solidity ^0.4.11;
import './SmartTokenController.sol';
import './SafeMath.sol';
import './interfaces/ISmartToken.sol';

/*
    Crowdsale v0.1

    The crowdsale version of the smart token controller, allows contributing ether in exchange for DAB founder tokens
    The price remains fixed for the entire duration of the token sale
*/
contract CrowdsaleController is SmartTokenController, SafeMath {
    struct Founder{
        uint256 contributed;
    }

    uint256 public constant DURATION = 14 days;                 // crowdsale duration
    uint256 public constant TOKEN_PRICE_N = 1;                  // initial price in wei (numerator)
    uint256 public constant TOKEN_PRICE_D = 100;                // initial price in wei (denominator)
    uint256 public constant MAX_GAS_PRICE = 50000000000 wei;    // maximum gas price for contribution transactions
    uint256 public constant TOTAL_ETHER_CAP = 5000 ether;       // total ether contribution cap
    uint256 public constant MAX_CONTRIBUTION = 5 ether;         // max ether a founder can contribute

    string public version = '0.1';

    uint256 public startTime = 0;                               // crowdsale start time (in seconds)
    uint256 public endTime = 0;                                 // crowdsale end time (in seconds)
    uint256 public totalEtherContributed = 0;                   // ether contributed so far
    uint256 public totalDepositTokenRedeemed = 0;               // founder redeemed deposit token
    uint256 public totalCreditTokenRedeemed = 0;                // founder redeemed credit token
    address public beneficiary = 0x0;                           // address to receive all ether contributions
    address public cashier = 0x0;                               // cashier address
    mapping (address => Founder) public founders;               // founders

    ISmartToken public depositToken = ISmartToken(0x0);         // depositToken address
    ISmartToken public creditToken = ISmartToken(0x0);          // creditToken address

    // triggered on each contribution
    event Contribution(address indexed _contributor, uint256 _amount, uint256 _return);
    event ConversionToDeposit(address indexed _contributor, uint256 _amount);
    event ConversionToCredit(address indexed _contributor, uint256 _amount);

    /**
        @dev constructor

        @param _token          smart token the crowdsale is for
        @param _startTime      crowdsale start time
        @param _beneficiary    address to receive all ether contributions
    */
    function CrowdsaleController(ISmartToken _token, uint256 _startTime, address _beneficiary)
        SmartTokenController(_token)
        validAddress(_beneficiary)
        earlierThan(_startTime)
    {
        startTime = _startTime;
        endTime = startTime + DURATION;
        beneficiary = _beneficiary;
    }

    // verifies that an amount is greater than zero
    modifier validAmount(uint256 _amount){
        require(_amount > 0);
        _;
    }

    // verifies that an founder does not contribute more than max contribution
    modifier validFounder(){
        require(safeAdd(founders[msg.sender].contributed, msg.value) <= MAX_CONTRIBUTION);
        _;
    }

    // verifies that the gas price is lower than 50 gwei
    modifier validGasPrice() {
        assert(tx.gasprice <= MAX_GAS_PRICE);
        _;
    }

    // ensures that it's earlier than the given time
    modifier earlierThan(uint256 _time) {
        assert(now < _time);
        _;
    }

    // ensures that the current time is between _startTime (inclusive) and _endTime (exclusive)
    modifier between(uint256 _startTime, uint256 _endTime) {
        assert(now >= _startTime && now < _endTime);
        _;
    }

    // ensures that we didn't reach the ether cap
    modifier etherCapNotReached(uint256 _contribution) {
        assert(safeAdd(totalEtherContributed, _contribution) <= TOTAL_ETHER_CAP);
        _;
    }

    // ensures that we set the redeem address
    modifier validRedeem() {
        assert(address(depositToken) != 0x0);
        assert(address(creditToken) != 0x0);
        assert(cashier != 0x0);
        _;
    }

    /**
        @dev set the deposit token address

        @param _depositToken    the deposit token address

    */
    function setDepositToken(ISmartToken _depositToken)
        public
        ownerOnly
        validAddress(_depositToken)
    {
        depositToken = _depositToken;
    }

    /**
        @dev set the credit token address

        @param _creditToken    the credit token address

    */
    function setCreditToken(ISmartToken _creditToken)
        public
        ownerOnly
        validAddress(_creditToken)
    {
        creditToken = _creditToken;
    }

    /**
        @dev set the cashier address

        @param _cashier    the cashier address

    */
    function setCashier(address _cashier)
        public
        ownerOnly
        validAddress(_cashier)
    {
        cashier = _cashier;
    }

    /**
        @dev convert the DAB founder token to deposit token at ratio of 1:1

        @param _amount    the amount to conversion

    */
    function convertToDepositToken(uint256 _amount)
        validRedeem
        validAmount(_amount)
    {
        token.destroy(msg.sender, _amount);
        assert(depositToken.transferFrom(cashier, msg.sender, _amount));
        totalDepositTokenRedeemed = safeAdd(totalDepositTokenRedeemed, _amount);

        ConversionToDeposit(msg.sender, _amount);
    }

    /**
        @dev convert the DAB founder token to credit token at ratio of 1:1

        @param _amount    the amount to conversion

    */
    function convertToCreditToken(uint256 _amount)
        validRedeem
        validAmount(_amount)
    {
        token.destroy(msg.sender, _amount);
        assert(depositToken.transferFrom(cashier, msg.sender, _amount));
        totalCreditTokenRedeemed = safeAdd(totalCreditTokenRedeemed, _amount);

        ConversionToCredit(msg.sender, _amount);
    }

    /**
        @dev computes the number of tokens that should be issued for a given contribution

        @param _contribution    contribution amount

        @return computed number of tokens
    */
    function computeReturn(uint256 _contribution) public constant returns (uint256) {
        return safeMul(_contribution, TOKEN_PRICE_D) / TOKEN_PRICE_N;
    }

    /**
        @dev ETH contribution
        can only be called during the crowdsale

        @return tokens issued in return
    */
    function contribute()
        public
        payable
        between(startTime, endTime)
        returns (uint256 amount)
    {
        return processContribution();
    }

    /**
        @dev handles contribution logic
        note that the Contribution event is triggered using the sender as the contributor, regardless of the actual contributor

        @return tokens issued in return
    */
    function processContribution() private
        active
        validGasPrice
        validFounder
        etherCapNotReached(msg.value)
        returns (uint256 amount)
    {
        uint256 tokenAmount = computeReturn(msg.value);
        assert(beneficiary.send(msg.value)); // transfer the ether to the beneficiary account
        totalEtherContributed = safeAdd(totalEtherContributed, msg.value); // update the total contribution amount
        token.issue(msg.sender, tokenAmount); // issue new funds to the contributor in the smart token
        founders[msg.sender].contributed = safeAdd(founders[msg.sender].contributed, msg.value);

        Contribution(msg.sender, msg.value, tokenAmount);
        return tokenAmount;
    }

    // fallback
    function() payable {
        contribute();
    }
}
