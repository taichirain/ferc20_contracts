// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// This is common token interface, get balance of owner's token by ERC20/ERC721/ERC1155.
interface ICommonToken {
    function balanceOf(address owner) external returns(uint256);
}

// This contract is extended from ERC20
contract Inscription is ERC20 {
    uint256 public cap;                 // Max amount
    uint256 public limitPerMint;        // Limitaion of each mint
    uint256 public inscriptionId;       // Inscription Id
    uint256 public maxMintSize;         // max mint size, that means the max mint quantity is: maxMintSize * limitPerMint
    uint256 public freezeTime;          // The frozen time (interval) between two mints is a fixed number of seconds. You can mint, but you will need to pay an additional mint fee, and this fee will be double for each mint.
    address public onlyContractAddress; // Only addresses that hold these assets can mint
    uint256 public onlyMinQuantity;     // Only addresses that the quantity of assets hold more than this amount can mint
    uint256 public baseFee;             // base fee of the second mint after frozen interval. The first mint after frozen time is free.

    address payable public inscriptionFactory;

    mapping(address => uint256) public lastMintTimestamp;   // record the last mint timestamp of account
    mapping(address => uint256) public mintTimes;           // record the mint times of account

    constructor(
        string memory _name,            // token name
        string memory _tick,            // token tick, same as symbol. must be 4 characters.
        uint256 _cap,                   // Max amount
        uint256 _limitPerMint,          // Limitaion of each mint
        uint256 _inscriptionId,         // Inscription Id
        uint256 _maxMintSize,           // max mint size, that means the max mint quantity is: maxMintSize * limitPerMint
        uint256 _freezeTime,            // The frozen time (interval) between two mints is a fixed number of seconds. You can mint, but you will need to pay an additional mint fee, and this fee will be double for each mint.
        address _onlyContractAddress,   // Only addresses that hold these assets can mint
        uint256 _onlyMinQuantity,       // Only addresses that the quantity of assets hold more than this amount can mint
        uint256 _baseFee,               // base fee of the second mint after frozen interval. The first mint after frozen time is free.
        address payable _inscriptionFactory
    ) ERC20(_name, _tick) {
        require(_cap >= _limitPerMint, "Limit per mint exceed cap");
        cap = _cap;
        limitPerMint = _limitPerMint;
        inscriptionId = _inscriptionId;
        maxMintSize = _maxMintSize;
        freezeTime = _freezeTime;
        onlyContractAddress = _onlyContractAddress;
        onlyMinQuantity = _onlyMinQuantity;
        baseFee = _baseFee;
        inscriptionFactory = _inscriptionFactory;
    }

    function mint(address _to) payable external {
        // Check if the quantity after mint will exceed the cap
        require(totalSupply() + limitPerMint <= cap, "Touched cap");
        // Check if the assets in the msg.sender is satisfied
        require(onlyContractAddress == address(0x0) || ICommonToken(onlyContractAddress).balanceOf(msg.sender) >= onlyMinQuantity, "You don't have required assets");

        if(lastMintTimestamp[msg.sender] + freezeTime > block.timestamp) {
            // In the frozen time, charge extra tip by eth
            mintTimes[msg.sender] = mintTimes[msg.sender] + 1;
            // The min extra tip is doule of last mint
            uint256 fee = baseFee * 2 ** (mintTimes[msg.sender] - 1);
            // Check if the tip is high than the min extra fee
            require(msg.value >= fee, "Must send some ETH as fee");
            // Check the user's balance
            require(payable(msg.sender).balance >= msg.value, "Balance not enough");
            // Transfer the tip to InscriptionFactory smart contract
            inscriptionFactory.transfer(msg.value);
        } else {
            // Out of frozen time, free mint. Reset the timestamp and mint times.
            mintTimes[msg.sender] = 0;
            lastMintTimestamp[msg.sender] = block.timestamp;
        }
        // Do mint
        _mint(_to, limitPerMint);
    }

    function batchMint(address _to, uint256 _num) external {
        require(_num <= maxMintSize, "exceed max mint size");
        require(totalSupply() + _num * limitPerMint <= cap, "Touch cap");
        for(uint256 i = 0; i < _num; i++) _mint(_to, limitPerMint);
    }

    function getMintFee() external view returns(uint256 times, uint256 fee) {
        if(lastMintTimestamp[msg.sender] + freezeTime > block.timestamp) {
            times = mintTimes[msg.sender] + 1;
            fee = baseFee * 2 ** (times - 1);
        }
    }
}
