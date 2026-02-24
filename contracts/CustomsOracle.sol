// SPDX-License-Identifier: MIT

// PART II — Customs Oracle Integration
// Oracle allows:
// - Verification of live MFN rates
// - Real-time CN classification
// - Origin cross-border validation
// - WTO compliance confirmation
//

pragma solidity ^0.8.20;

//NOTE - I do not think this is needed for disertation, this will fetch additional data by oracles, in RL probably needed, but here it is questionable
contract CustomsOracle {
    address public oracleAuthority;
    modifier onlyOracle() {
        require(msg.sender == oracleAuthority, "Not oracle");
        _;
    }

    constructor() {
        oracleAuthority = msg.sender;
    }

    mapping(string => uint256) public liveMFNRates;
    event MFNUpdated(string hsCode, uint256 rate);

    function updateMFN(string memory hsCode, uint256 rate) external onlyOracle {
        liveMFNRates[hsCode] = rate;
        emit MFNUpdated(hsCode, rate);
    }

    function getMFN(string memory hsCode) external view returns (uint256) {
        return liveMFNRates[hsCode];
    }
}
