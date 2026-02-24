// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract EUWithdrawalRegistry {
    address public admin;
    mapping(string => bool) public euMembers;
    mapping(string => bool) public ceftaActive;
    event Withdrawn(string country);
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    constructor(string[] memory initialMembers) {
        admin = msg.sender;
        for (uint i = 0; i < initialMembers.length; i++) {
            ceftaActive[initialMembers[i]] = true;
        }
    }

    function markEUMember(string memory country) external onlyAdmin {
        euMembers[country] = true;
        ceftaActive[country] = false;
        emit Withdrawn(country);
    }

    function isActive(string memory country) external view returns (bool) {
        return ceftaActive[country];
    }
}
