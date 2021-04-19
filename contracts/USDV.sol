// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iUTILS.sol";
import "./iVADER.sol";
import "./iROUTER.sol";
import "./iPOOLS.sol";
import "./iSYNTH.sol";

import "hardhat/console.sol";

    //======================================VADER=========================================//
contract USDV is iERC20 {

    // ERC-20 Parameters
    string public override name; string public override symbol;
    uint public override decimals; uint public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;

    // Parameters
    bool private inited;
    uint public currentEra;
    uint public nextEraTime;
    uint public erasToEarn;
    uint public minGrantTime;
    uint public lastGranted;
    uint public blockDelay;

    address public VADER;
    address public ROUTER;
    address public POOLS;

    uint public minimumDepositTime;
    uint public totalWeight;
    uint public totalRewards;

    mapping(address => uint) private mapToken_totalFunds;
    mapping(address => uint) private mapMember_weight;
    mapping(address => mapping(address => uint)) private mapMemberToken_deposit;
    mapping(address => mapping(address => uint)) private mapMemberToken_reward;
    mapping(address => mapping(address => uint)) private mapMemberToken_lastTime;
    mapping(address => uint) public lastBlock;

    // Events
    event MemberDeposits(address indexed token, address indexed member, uint newDeposit, uint totalDeposit, uint weight, uint totalWeight);
    event MemberWithdraws(address indexed token, address indexed member, uint amount, uint weight, uint totalWeight);
    event MemberHarvests(address indexed token, address indexed member, uint amount, uint weight, uint totalWeight);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO(), "Not DAO");
        _;
    }
    // Stop flash attacks
    modifier flashProof() {
        require(isMature(), "No flash");
        _;
    }
    function isMature() public view returns(bool matured){
        if(lastBlock[tx.origin] + blockDelay <= block.number){
            return true;
        }
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor() {
        name = 'VADER STABLE DOLLAR';
        symbol = 'USDV';
        decimals = 18;
        totalSupply = 0;
    }
    function init(address _vader, address _router, address _pool) public {
        require(inited == false);
        inited = true;
        VADER = _vader;
        ROUTER = _router;
        POOLS = _pool;
        iERC20(VADER).approve(ROUTER, type(uint).max);
        _approve(address(this), ROUTER, type(uint).max);
        currentEra = 1;
        nextEraTime = block.timestamp + iVADER(VADER).secondsPerEra();
        erasToEarn = 100;
        minimumDepositTime = 1;
        blockDelay = 0;
        minGrantTime = 2592000;     // 30 days
    }

    //========================================iERC20=========================================//
    function balanceOf(address account) public view override returns (uint) {
        return _balances[account];
    }
    function allowance(address owner, address spender) public view virtual override returns (uint) {
        return _allowances[owner][spender];
    }
    // iERC20 Transfer function
    function transfer(address recipient, uint amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    // iERC20 Approve, change allowance functions
    function approve(address spender, uint amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function _approve(address owner, address spender, uint amount) internal virtual {
        require(owner != address(0), "sender");
        require(spender != address(0), "spender");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    // iERC20 TransferFrom function
    function transferFrom(address sender, address recipient, uint amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    // TransferTo function
    function transferTo(address recipient, uint amount) public virtual override returns (bool) {
        _transfer(tx.origin, recipient, amount);
        return true;
    }

    // Internal transfer function
    function _transfer(address sender, address recipient, uint amount) internal virtual {
        require(sender != address(0), "sender");
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        _checkIncentives();
    }
    // Internal mint (upgrading and daily emissions)
    function _mint(address account, uint amount) internal virtual {
        require(account != address(0), "recipient");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
    // Burn supply
    function burn(uint amount) public virtual override {
        _burn(msg.sender, amount);
    }
    function burnFrom(address account, uint amount) public virtual override {
        uint decreasedAllowance = allowance(account, msg.sender)- amount;
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }
    function _burn(address account, uint amount) internal virtual {
        require(account != address(0), "address err");
        _balances[account] -= amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(uint _one, uint _two, uint _three, uint _four) public onlyDAO {
        erasToEarn = _one;
        minimumDepositTime = _two;
        blockDelay = _three;
        minGrantTime = _four;
    }
    // Can issue grants
    function grant(address recipient, uint amount) public onlyDAO {
        require(amount <= (reserveUSDV() / 10), "not more than 10%");
        require((block.timestamp - lastGranted) >= minGrantTime, "not too fast");
        _transfer(address(this), recipient, amount); 
    }

   //======================================INCENTIVES========================================//
    // Internal - Update incentives function
    function _checkIncentives() private {
        if (block.timestamp >= nextEraTime && emitting()) {                  // If new Era
            currentEra += 1;                                        // Increment Era
            nextEraTime = block.timestamp + iVADER(VADER).secondsPerEra(); 
            uint _balance = iERC20(VADER).balanceOf(address(this)); // Get spare VADER
            uint _USDVShare = _twothirds(_balance);                 // Get 2/3rds
            _convert(address(this), _USDVShare);                    // Convert it
            iROUTER(ROUTER).pullIncentives(iERC20(VADER).balanceOf(address(this)), _USDVShare / 2);                         // Pull incentives over
        }
    }
    
    //======================================ASSET MINTING========================================//
    // Contracts to convert
    function convert(uint amount) public returns(uint) {
        return convertForMember(msg.sender, amount);
    }
    // Contracts to convert for members
    function convertForMember(address member, uint amount) public returns(uint) {
        getFunds(VADER, amount);
        return _convert(member, amount);
    }
    // Internal convert
    function _convert(address _member, uint amount) internal flashProof returns(uint _convertAmount){
        lastBlock[tx.origin] = block.number;
        iERC20(VADER).burn(amount);
        _convertAmount = iROUTER(ROUTER).getUSDVAmount(amount);
        _mint(_member, _convertAmount);
        return _convertAmount;
    }
    // Contracts to redeem
    function redeem(uint amount) public returns(uint convertAmount) {
        return redeemForMember(msg.sender, amount);
    }
    // Contracts to redeem for members
    function redeemForMember(address member, uint amount) public returns(uint redeemAmount) {
        _transfer(msg.sender, VADER, amount);                   // Move funds
        redeemAmount = iVADER(VADER).redeemToMember(member);
        lastBlock[tx.origin] = block.number;
        return redeemAmount;
    }

    //======================================DEPOSITS========================================//

    // Holders to deposit for Interest Payments
    function deposit(address token, uint amount) public {
        depositForMember(token, msg.sender, amount);
    }
    // Wrapper for contracts
    function depositForMember(address token, address member, uint amount) public {
        require(token==address(this) || (iPOOLS(POOLS).isSynth(token) && iPOOLS(POOLS).isAsset(iSYNTH(token).TOKEN())));
        getFunds(token, amount);
        _deposit(token, member, amount);
    }
    function _deposit(address _token, address _member, uint _amount) internal {
        mapMemberToken_lastTime[_member][_token] = block.timestamp;
        mapMemberToken_deposit[_member][_token] += _amount; // Record balance for member
        uint _weight;
        if(_token==address(this)){
            _weight = _amount;
        } else {
            _weight = iUTILS(UTILS()).calcValueInBase(iSYNTH(_token).TOKEN(), _amount);
        }
        mapToken_totalFunds[_token] += _amount;
        mapMember_weight[_member] += _weight;
        totalWeight += _weight;
        emit MemberDeposits(_token, _member, _amount, mapToken_totalFunds[_token], _weight, totalWeight);
    }

    //====================================== HARVEST ========================================//

    // Harvest, get payment, allocate, increase weight
    function harvest(address token) public returns(uint reward){
        address _member = msg.sender;
        reward = calcCurrentReward(token, _member);
        mapMemberToken_lastTime[_member][token] = block.timestamp;
        mapMemberToken_reward[_member][token] += reward;
        totalRewards += reward;
        uint _weight;
        if(token==address(this)){
            _weight = reward;
        } else {
            _weight = iUTILS(UTILS()).calcValueInBase(iSYNTH(token).TOKEN(), reward);
        }
        mapMember_weight[_member] += _weight;
        totalWeight += _weight;
        emit MemberHarvests(token, _member, reward, _weight, totalWeight);
        return reward;
    }

    // Get the payment owed for a member
    function calcCurrentReward(address token, address member) public view returns(uint _reward){
        uint _secondsSinceClaim = block.timestamp - mapMemberToken_lastTime[member][token];        // Get time since last claim
        uint _share = calcReward(member);                                              // Get share of rewards for member
        _reward = (_share * _secondsSinceClaim) / iVADER(VADER).secondsPerEra();   // Get owed amount, based on per-day rates
        uint _reserve = reserveUSDV();
        if(_reward >= _reserve) {
            _reward = _reserve;                                                         // Send full reserve if the last
        }
        return _reward;
    }

    function calcReward(address member) public view returns(uint){
        uint _weight = mapMember_weight[member];
        uint _reserve = reserveUSDV() / erasToEarn;                               // Deplete reserve over a number of eras
        return iUTILS(UTILS()).calcShare(_weight, totalWeight, _reserve);         // Get member's share of that
    }

//====================================== WITHDRAW ========================================//

    // Members to withdraw
    function withdraw(address token, uint basisPoints) public returns(uint redeemedAmount) {
        address _member = msg.sender;
        redeemedAmount = _processWithdraw(token, _member, basisPoints);                         // get amount to withdraw
        sendFunds(token, _member, redeemedAmount);
        return redeemedAmount;
    }
    function _processWithdraw(address _token, address _member, uint _basisPoints) internal returns(uint _amount) {
        require((block.timestamp - mapMemberToken_lastTime[_member][_token]) >= minimumDepositTime, "DepositTime");    // stops attacks
        uint _reward = iUTILS(UTILS()).calcPart(_basisPoints, mapMemberToken_reward[_member][_token]); // share of reward
        mapMemberToken_reward[_member][_token] -= _reward;
        totalRewards -= _reward;
        if(_token!=address(this)){
            _reward = iUTILS(UTILS()).calcSwapValueInToken(iSYNTH(_token).TOKEN(), _reward);
            _transfer(address(this), POOLS, _reward);
            _reward = iPOOLS(POOLS).mintSynth(address(this), iSYNTH(_token).TOKEN(), address(this));
        }
        uint _principle = iUTILS(UTILS()).calcPart(_basisPoints, mapMemberToken_deposit[_member][_token]); // share of deposits
        mapMemberToken_deposit[_member][_token] -= _principle;                                   
        mapToken_totalFunds[_token] -= _principle;
        uint _weight = iUTILS(UTILS()).calcPart(_basisPoints, mapMember_weight[_member]);
        mapMember_weight[_member] -= _weight; 
        totalWeight -= _weight;                                                     // reduce for total
        emit MemberWithdraws(_token, _member, _amount, _weight, totalWeight);
        return (_principle + _reward);
    }

    //============================== ASSETS ================================//

    function getFunds(address token, uint amount) internal{
        if(token == address(this)){
            _transfer(msg.sender, address(this), amount);
        } else {
            if(tx.origin==msg.sender){
                require(iERC20(token).transferTo(address(this), amount));
            }else{
                require(iERC20(token).transferFrom(msg.sender, address(this), amount));
            }
        }
    }
    function sendFunds(address token, address member, uint amount) internal{
        if(token == address(this)){
            _transfer(address(this), member, amount);
        } else {
            require(iERC20(token).transfer(member, amount));
        }
    }

    //============================== HELPERS ================================//

    function reserveUSDV() public view returns(uint){
        return balanceOf(address(this)) - mapToken_totalFunds[address(this)] - totalRewards; // Balance - deposits - rewards
    }

    function _twothirds(uint _amount) internal pure returns(uint){
        return (_amount * 2) / 3;
    }
    function getTokenDeposits(address token) external view returns(uint){
        return mapToken_totalFunds[token];
    }
    function getMemberDeposit(address token, address member) external view returns(uint){
        return mapMemberToken_deposit[member][token];
    }
    function getMemberReward(address token, address member) external view returns(uint){
        return mapMemberToken_reward[member][token];
    }
    function getMemberWeight(address member) external view returns(uint){
        return mapMember_weight[member];
    }
    function getMemberLastTime(address token, address member) external view returns(uint){
        return mapMemberToken_lastTime[member][token];
    }
    function UTILS() public view returns(address){
        return iVADER(VADER).UTILS();
    }
    function DAO() public view returns(address){
        return iVADER(VADER).DAO();
    }
    function emitting() public view returns(bool){
        return iVADER(VADER).emitting();
    }

}