// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVerifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata publicSignals
    ) external view returns (bool);
}

contract ZKOriginRegistry {
    IVerifier public verifier;
    address public admin;

    constructor(address _verifier) {
        verifier = IVerifier(_verifier);
        admin = msg.sender;
    }

    /*
publicSignals layout:
[0] HS Code hash
[1] Exporting country hash
[2] Non-originating % (encoded)
*/
    function verifyOriginZK(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata publicSignals
    ) external view returns (bool) {
        return verifier.verifyProof(a, b, c, publicSignals);
    }
}
