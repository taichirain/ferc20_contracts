// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/InscriptionFactory.sol";

contract InscriptionFactoryScript is Script {
    function run() external {
        vm.startBroadcast();

        InscriptionFactory factory = new InscriptionFactory();

        vm.stopBroadcast();
    }
}

