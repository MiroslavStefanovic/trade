// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AnnexRegistry {
    address public admin;
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /*
==========================================================
ANNEX 1 – Allowed Agricultural HS Codes
==========================================================
*/
    mapping(string => bool) public allowedHS;

    function addHSCode(string memory hsCode) external onlyAdmin {
        allowedHS[hsCode] = true;
    }

    function verifyHS(string memory hsCode) external view returns (bool) {
        return allowedHS[hsCode];
    }

    /*
==========================================================
ANNEX 2 – Tariff Reductions (basic duty snapshot)
==========================================================
*/
    struct TariffSchedule {
        uint256 baseDuty;
        uint256 reducedDuty;
        bool reductionApplied;
    }
    mapping(string => TariffSchedule) public tariffSchedules;

    function setTariffSchedule(
        string memory hsCode,
        uint256 baseDuty,
        uint256 reducedDuty
    ) external onlyAdmin {
        tariffSchedules[hsCode] = TariffSchedule(baseDuty, reducedDuty, true);
    }

    /*
==========================================================
ANNEX 3 – Country Specific Quotas
==========================================================
*/
    struct Quota {
        uint256 max;
        uint256 used;
    }
    mapping(string => mapping(string => Quota)) public countryQuotas;

    function setQuota(
        string memory country,
        string memory hsCode,
        uint256 maxAmount
    ) external onlyAdmin {
        countryQuotas[country][hsCode] = Quota(maxAmount, 0);
    }

    function consumeQuota(
        string memory country,
        string memory hsCode,
        uint256 amount
    ) external {
        Quota storage q = countryQuotas[country][hsCode];
        require(q.used + amount <= q.max, "Quota exceeded");
        q.used += amount;
    }

    //TODO return bool, probably better to return uint256 with amount
    //NOTE amount decimals to be mentioned in documentation, e.g. 1000 = 10.00 tons
    function quotaAvailable(
        string memory country,
        string memory hsCode,
        uint256 amount
    ) external view returns (bool) {
        Quota memory q = countryQuotas[country][hsCode];
        return q.used + amount <= q.max;
    }
}
