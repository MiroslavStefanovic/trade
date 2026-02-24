// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DynamicTariffMatrix {
    address public admin;
    struct TariffCell {
        uint256 quota;
        uint256 used;
        uint256 inQuotaDuty;
        uint256 outQuotaDuty;
        bool exists;
    }
    /*
exporter =&gt; importer =&gt; hsCode =&gt; TariffCell
*/
    mapping(string => mapping(string => mapping(string => TariffCell)))
        public matrix;
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function setTariffCell(
        string memory exporter,
        string memory importer,
        string memory hsCode,
        uint256 quota,
        uint256 inQuotaDuty,
        uint256 outQuotaDuty
    ) external onlyAdmin {
        matrix[exporter][importer][hsCode] = TariffCell(
            quota,
            0,
            inQuotaDuty,
            outQuotaDuty,
            true
        );
    }

    function calculateDuty(
        string memory exporter,
        string memory importer,
        string memory hsCode,
        uint256 quantity,
        uint256 value
    ) external returns (uint256) {
        TariffCell storage cell = matrix[exporter][importer][hsCode];
        require(cell.exists, "No tariff rule");
        if (cell.used + quantity <= cell.quota) {
            cell.used += quantity;
            return (value * cell.inQuotaDuty) / 100;
        } else {
            cell.used += quantity;
            return (value * cell.outQuotaDuty) / 100;
        }
    }
}
