// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 该合约用于部署铭文代币
// 特点：
// 1- 遵守BRC20标准，限定四个字母，且忽略大小写，一律转换为小写。
// 2- 符合ERC20标准，有name属性。可以在所有以太坊的DEX中交易。
// 3- 为防女巫攻击造成铸造过程不公平，规定了铸造冷冻期。
// 不在冷冻期内，可以免费铸造；一旦免费铸造成功，冷冻期启动，在冷冻期内铸造，需要支付额外的费用（ETH），并且每次铸造费用是上一次的两倍。
// 冷冻期可以在部署代币时，由部署人设定，一旦设定，不能修改。
// 冷冻期内铸币产生的额外费用归本合约所有。
// 基础费用（即免费后第一次额外费用）为0.00025ETH
// 用户在铸造时，需要手动输入小费（tip），该小费必须大于等于额外的费用。前端可以通过 getMintFee 方法获得需额外支付的最低ETH费用。
// 5- 为防女巫攻击，部署者还可以设定参与铸造账户拥有的资产条件，如改账户是否拥有某个NFT或ERC20代币，并配置最少数量。
// 6- 为防女巫攻击，设定了 maxMintSize，即每次铸造的最多张数。该数量由部署人在部署铭文代币时设定，一旦设定，不能修改。

import "./Inscription.sol";
import "./String.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract InscriptionFactory is Ownable{
    using String for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _inscriptionNumbers;

    uint8 public maxTickSize = 4;                   // tick(symbol) length is 4.
    uint256 public baseFee = 250000000000000;       // Will charge 0.00025 ETH as extra min tip from the second time of mint in the frozen period. And this tip will be double for each mint.

    mapping(uint256 => Token) private inscriptions; // key is inscription id, value is token data
    mapping(string => uint256) private ticks;       // Key is tick, value is inscription id

    event DeployInscription(
        uint256 indexed id, 
        string tick, 
        string name, 
        uint256 cap, 
        uint256 limitPerMint, 
        address inscriptionAddress, 
        uint256 timestamp
    );

    struct Token {
        string tick;            // same as symbol in ERC20
        string name;            // full name of token
        uint256 cap;            // Hard cap of token
        uint256 limitPerMint;   // Limitation per mint
        address addr;           // Contract address of inscribed token 
        uint256 timestamp;      // Inscribe timestamp
    }

    constructor() {
        // The inscription id will be from 1, not zero.
        _inscriptionNumbers.increment();
    }

    // Let this contract accept ETH as tip
    receive() external payable {}
    
    function deploy(
        string memory _name,
        string memory _tick,
        uint256 _cap,
        uint256 _limitPerMint,
        uint256 _maxMintSize, // The max lots of each mint
        uint256 _freezeTime, // Freeze seconds between two mint, during this freezing period, the mint fee will be increased 
        address _onlyContractAddress, // Only the holder of this asset can mint, optional
        uint256 _onlyMinQuantity // The min quantity of asset for mint, optional
    ) external returns (address _inscriptionAddress) {
        require(String.strlen(_tick) == maxTickSize, "Tick lenght should be 4");
        require(_cap >= _limitPerMint, "Limit per mint exceed cap");

        _tick = String.toLower(_tick);
        require(this.getIncriptionIdByTick(_tick) == 0, "tick is existed");

        // Create inscription contract
        bytes memory bytecode = type(Inscription).creationCode;
        uint256 _id = _inscriptionNumbers.current();
		bytecode = abi.encodePacked(bytecode, abi.encode(
            _name, 
            _tick, 
            _cap, 
            _limitPerMint, 
            _id, 
            _maxMintSize,
            _freezeTime,
            _onlyContractAddress,
            _onlyMinQuantity,
            baseFee,
            address(this)
        ));
		bytes32 salt = keccak256(abi.encodePacked(_id));
		assembly {
			_inscriptionAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
			if iszero(extcodesize(_inscriptionAddress)) {
				revert(0, 0)
			}
		}
        inscriptions[_id] = Token(_tick, _name, _cap, _limitPerMint, _inscriptionAddress, block.timestamp);
        ticks[_tick] = _id;

        _inscriptionNumbers.increment();
        emit DeployInscription(_id, _tick, _name, _cap, _limitPerMint, _inscriptionAddress, block.timestamp);
    }

    function getInscriptionAmount() external view returns(uint256) {
        return _inscriptionNumbers.current() - 1;
    }

    function getIncriptionIdByTick(string memory _tick) external view returns(uint256) {
        return ticks[String.toLower(_tick)];
    }

    function getIncriptionById(uint256 _id) external view returns(Token memory, uint256) {
        Token memory token = inscriptions[_id];
        return (inscriptions[_id], Inscription(token.addr).totalSupply());
    }

    function getIncriptionByTick(string memory _tick) external view returns(Token memory, uint256) {
        Token memory token = inscriptions[this.getIncriptionIdByTick(_tick)];
        return (inscriptions[this.getIncriptionIdByTick(_tick)], Inscription(token.addr).totalSupply());
    }

    // Fetch inscription data by page no, page size, type and search keyword
    function getIncriptions(
        uint256 _pageNo, 
        uint256 _pageSize, 
        uint256 _type, // 0- all, 1- in-process, 2- ended
        string memory _searchBy
    ) external view returns(
        Token[] memory inscriptions_, 
        uint256[] memory totalSupplies_
    ) {
        // if _searchBy is not empty, the _pageNo and _pageSize should be set to 1
        uint256 totalInscription = this.getInscriptionAmount();
        uint256 pages = (totalInscription - 1) / _pageSize + 1;
        require(_pageNo > 0 && _pageSize > 0 && pages > 0 && _pageNo <= pages, "Params wrong");

        inscriptions_ = new Token[](_pageSize);
        totalSupplies_ = new uint256[](_pageSize);

        Token[] memory _inscriptions = new Token[](totalInscription);
        uint256[] memory _totalSupplies = new uint256[](totalInscription);

        uint256 index = 0;
        for(uint256 i = 1; i <= totalInscription; i++) {
            (Token memory _token, uint256 _totalSupply) = this.getIncriptionById(i);
            if(_type == 1 && _totalSupply == _token.cap) continue;
            else if(_type == 2 && _totalSupply < _token.cap) continue;
            else if(!String.compareStrings(_searchBy, "") && !String.compareStrings(String.toLower(_searchBy), _token.tick)) continue;
            else {
                _inscriptions[index] = _token;
                _totalSupplies[index] = _totalSupply;
                index++;
            }
        }

        for(uint256 i = 0; i < _pageSize; i++) {
            uint256 id = (_pageNo - 1) * _pageSize + i;
            if(id < index) {
                inscriptions_[i] = _inscriptions[id];
                totalSupplies_[i] = _totalSupplies[id];
            }
        }
    }

    // Withdraw the ETH tip from the contract
    function withdraw(address payable _to, uint256 _amount) external onlyOwner {
        require(_amount <= payable(address(this)).balance);
        _to.transfer(_amount);
    }

    // Update base fee
    function updateBaseFee(uint256 _fee) external onlyOwner {
        baseFee = _fee;
    }

    // Update character's length of tick
    function updateTickSize(uint8 _size) external onlyOwner {
        maxTickSize = _size;
    }

    // function test() external {
    //     for(uint256 i = 0; i < 1; i++) {
    // 		string memory _name = string(abi.encodePacked("Test coin #", (i + 1).toString()));
	//     	string memory _symbol = string(abi.encodePacked("tt#", (i + 1).toString()));
    //         this.deploy(
    //             _name,
    //             _symbol,
    //             10000000000000000000000,
    //             1000000000000000000000,
    //             10,
    //             180,
    //             address(0x0),
    //             0
    //         );
    //     }

    //     (Token memory inscription1, ) = this.getIncriptionById(2);
    //     address addr1 = inscription1.addr;
    //     Inscription(addr1).batchMint(msg.sender, 10);

    //     (Token memory inscription2, ) = this.getIncriptionById(4);
    //     address addr2 = inscription2.addr;
    //     Inscription(addr2).batchMint(msg.sender, 10);

    //     (Token memory inscription3, ) = this.getIncriptionById(7);
    //     address addr3 = inscription3.addr;
    //     Inscription(addr3).batchMint(msg.sender, 5);

    //     (Token memory inscription4, ) = this.getIncriptionById(8);
    //     address addr4 = inscription4.addr;
    //     Inscription(addr4).batchMint(msg.sender, 3);
    // }
}