pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VNRService is Ownable {
	/** USINGS */
	using SafeMath for uint256;

	/** STRUCTS */
	struct VName {
		bytes name;
		uint256 expires;
		address owner;
	}

	struct LockedBalance {
		uint256 expires;
		uint256 lockedBalance;
	}

	
	uint256 public lockNamePrice = 0.01 ether;
	uint256 public lockTime = 365 days;
	uint256 public registeredBytePrice = 0.0001 ether;
	uint8 public constant NAME_MIN_LENGTH = 3;
	uint8 public constant NAME_MAX_LENGTH = 30;
	uint16 public constant FRONTRUN_TIME = 5 minutes;
	uint256 private feesAmount = 0;

	
	mapping(bytes32 => VName) public vnames;
	mapping(bytes32 => uint256) public preRegisters;
	mapping(bytes32 => LockedBalance) public lockedBalances;

	
	 // MODIFIER
	modifier isAvailable(bytes memory _name) {
		bytes32 nameHash = getNameHash(_name);
		require(
			vnames[nameHash].expires == 0 ||
				vnames[nameHash].expires < block.timestamp,
			"Vanity name is not available."
		);
		_;
	}

	modifier isNameOwner(bytes memory name) {
		// @dev - get the hash of the name
		bytes32 nameHash = getNameHash(name);
		// @dev - check whether the msg.sender is the owner of the vanity name
		require(
			vnames[nameHash].owner == msg.sender &&
				vnames[nameHash].expires > block.timestamp,
			"You are not the owner of this vanity name."
		);
		_;
	}

	modifier isNameLengthAllowed(bytes memory _name) {
		// @dev - check if the provided name is with allowed length
		require(_name.length >= NAME_MIN_LENGTH, "Name is too short.");
		require(_name.length <= NAME_MAX_LENGTH, "Name is too long.");
		_;
	}

	modifier isPaymentEnough(bytes memory _name) {
		// @dev - checks if the sender value is enough to register the name
		uint256 namePrice = getNamePrice(_name);
		require(
			msg.value >= namePrice.add(lockNamePrice),
			"Insufficient amount."
		);
		_;
	}

	modifier isRegisterOpen(address _address, bytes memory _name) {
		bytes32 secret = keccak256(abi.encodePacked(_address, _name));
		require(
			preRegisters[secret] > 0,
			"No preregister for your vanity name"
		);
		require(
			block.timestamp > preRegisters[secret] + FRONTRUN_TIME,
			"Register not unlocked yet. 5 minutes cooldown"
		);
		_;
	}
	//EVENTS
	event VNameRegistered(bytes name, address owner, uint256 indexed timestamp);
	event VNameRenewed(bytes name, address owner, uint256 indexed timestamp);
	event VNameUnlocked(bytes name, uint256 indexed timestamp);

	/*
	 * @dev - function to pre-register a hashed vanity name. 
              It should be hashed address+name
	 * @param _hash - called address hashed with the desired name
	 */
	function preRegister(bytes32 _hash) external {
		preRegisters[_hash] = block.timestamp;
	}

	/*
	 * @dev - function to register vanity name
	 * @param name - vanity name to be registered
	 */
	function register(bytes memory _name)
		public
		payable
		isNameLengthAllowed(_name)
		isAvailable(_name)
		isRegisterOpen(msg.sender, _name)
		isPaymentEnough(_name)
	{
		// calculate the name hash
		bytes32 nameHash = getNameHash(_name);

		// calculate the name price
		uint256 namePrice = getNamePrice(_name);

		// create a new name entry with the provided fn parameters
		VName memory newVName = VName({
			name: _name,
			expires: block.timestamp + lockTime,
			owner: msg.sender
		});

		LockedBalance memory lb = LockedBalance({
			expires: block.timestamp + lockTime,
			lockedBalance: msg.value.sub(namePrice)
		});
		bytes32 key = keccak256(abi.encodePacked(msg.sender, _name));

		// save the vanity name and the locked balance to the storage
		vnames[nameHash] = newVName;
		lockedBalances[key] = lb;

		//Accumulate fees
		feesAmount += namePrice;
		// log vanity name registered
		emit VNameRegistered(_name, msg.sender, block.timestamp);
	}

	/*
	 * @dev - function to extend vanity name expiration date
	 * @param _name - name to be registered
	 */
	function renew(bytes memory _name) public payable isNameOwner(_name) {
		// calculate the name hash
		bytes32 nameHash = getNameHash(_name);

		// calculate the name price
		uint256 namePrice = getNamePrice(_name);

		require(msg.value == namePrice, "Invalid amount.");

		//Accumulate fees
		feesAmount += namePrice;

		// Increase lock time to the vanity expiration date
		vnames[nameHash].expires += lockTime;

		// Increase lock time to the locked balance expiration date
		bytes32 key = keccak256(abi.encodePacked(msg.sender, _name));
		lockedBalances[key].expires += lockTime;

		// log vanity name Renewed
		emit VNameRenewed(_name, msg.sender, block.timestamp);
	}

	/*
	 * @dev - Get name hash used for unique identifier
	 * @param name
	 * @return nameHash
	 */
	function getNameHash(bytes memory _name) public pure returns (bytes32) {
		// @dev - tightly pack parameters in struct for keccak256
		return keccak256(abi.encodePacked(_name));
	}

	/*
	 * @dev - Get price of name
	 * @param name
	 */
	function getNamePrice(bytes memory _name)
		public
		view
		isNameLengthAllowed(_name)
		returns (uint256)
	{
		//calculate price from name length
		return uint256(_name.length).mul(registeredBytePrice);
	}

	/*
	 * @dev - Get price of registering name
	 * @param name
	 */
	function getRegisterPrice(bytes memory _name)
		external
		view
		isNameLengthAllowed(_name)
		returns (uint256)
	{
		//calculate price from name length
		uint256 namePrice = getNamePrice(_name);
		return uint256(namePrice).add(lockNamePrice);
	}

	/**
	 * @dev - Set new lock name price
	 */
	function setLockNamePrice(uint256 _price) external onlyOwner {
		lockNamePrice = _price;
	}

	/**
	 * @dev - Set new blocking time
	 */
	function setLockTime(uint256 _lockTime) external onlyOwner {
		lockTime = _lockTime;
	}

	/**
	 * @dev - Set new registered byte name price
	 */
	function setRegisteredBytePrice(uint256 _registeredBytePrice)
		external
		onlyOwner
	{
		registeredBytePrice = _registeredBytePrice;
	}

	/*
	 * @dev - Get name hash used for unique identifier
	 * @param name
	 * @return nameHash
	 */
	function isNameAvailable(bytes memory _name)
		external
		view
		isAvailable(_name)
		isNameLengthAllowed(_name)
		returns (bool)
	{
		return true;
	}

	/*
	 * @dev - Get name owner
	 * @param _name
	 * @return owner
	 */
	function getNameOwner(bytes memory _name) external view returns (address) {
		// calculate the name hash
		bytes32 nameHash = getNameHash(_name);
		if (vnames[nameHash].expires < block.timestamp) {
			return address(0);
		}

		return vnames[nameHash].owner;
	}

	/*
	 * @dev - Get name hash used for unique identifier
	 * @param name
	 * @return nameHash
	 */
	function getPreRegisterHash(bytes memory _name)
		public
		view
		returns (bytes32)
	{
		// @dev - tightly pack parameters in struct for keccak256
		return keccak256(abi.encodePacked(msg.sender, _name));
	}

	/**
	 * @dev - Withdraw function
	 */
	function withdrawFees() external onlyOwner {
		require(feesAmount > 0, "No fees to withdraw");
		uint256 aux = feesAmount;
		feesAmount = 0;
		address _owner = owner();
		payable(_owner).transfer(aux);
	}

	/**
	 * @dev - Withdraw user's locked balance
	 */
	function withdrawLockedBalance(bytes memory _name) external {
		bytes32 key = keccak256(abi.encodePacked(msg.sender, _name));

		require(lockedBalances[key].lockedBalance > 0, "No balance to unlock");
		require(
			lockedBalances[key].expires < block.timestamp,
			"Balance still locked"
		);

		//Create aux to avoid reentrancy
		uint256 aux = lockedBalances[key].lockedBalance;
		lockedBalances[key].lockedBalance = 0;
		payable(msg.sender).transfer(aux);
	}
}