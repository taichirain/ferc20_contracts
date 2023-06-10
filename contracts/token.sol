// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "solmate/tokens/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

error NoPayMintPrice();
error WithdrawTransfer();
error MaxSupply();

contract SDUFECoin is ERC20, Ownable {
    
    uint256 public constant MINT_PRICE = 0.00000001 ether;
    uint256 public constant MAX_SUPPLY  = 1_000_000;

    constructor (
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20 (_name, _symbol, _decimals) {}

    function mintTo(address recipient) public payable {
        if (msg.value < MINT_PRICE) {
            revert NoPayMintPrice();
        } else {
            uint256 amount = msg.value / MINT_PRICE;
            uint256 nowAmount = totalSupply + amount;
            if (nowAmount <= MAX_SUPPLY) {
                _mint(recipient, amount);
            } else {
                revert MaxSupply();
            }
        }
    }

    function withdrawPayments(address payable payee) external onlyOwner {
        uint256 balance = address(this).balance;
        (bool transferTx, ) = payee.call{value: balance}("");
        if (!transferTx) {
            revert WithdrawTransfer();
        }
    }
}

