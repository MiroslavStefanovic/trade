// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal interface for CEFTA agreement checks.
/// @dev Only the fields needed for tariff calculation are exposed.
import { ITradeDefinitions } from "./ITradeDefinitions.sol";

interface ICeftaAgreement {

    function agreementActive() external view returns (bool);

    function memberCount() external view returns (uint256);

    function allowedHS(string memory hsCode) external view returns (bool);

    function isMember(address account) external view returns (bool);

    function getMembers()
        external
        view
        returns (ITradeDefinitions.Party[] memory);

    function isMemberCountry(uint16 country) external view returns (bool);

    function addMember(address member, uint16 country) external;

    function removeMember(address member) external;

    function setHSCode(string memory hsCode) external;

    function setQuota(
        uint16 exporterCountry,
        uint16 importerCountry,
        string memory hsCode,
        uint256 maxAmount
    ) external;

    function setAgreementActive(bool active) external;

    function setCeftaTrade(address trade) external;

    function registerTradeContract(address tradeContract) external;

    function updateTradeQuantity(
        uint16 exporterCountry,
        uint16 importerCountry,
        string memory hsCode,
        uint256 oldQuantity,
        uint256 newQuantity
    ) external;

    function quotaAvailable(
        uint16 exporterCountry,
        uint16 importerCountry,
        string memory hsCode
    ) external view returns (uint256);

    function recordTrade(
        ITradeDefinitions.Party memory exporter,
        ITradeDefinitions.Party memory importer,
        string memory hsCode,
        uint256 quantity,
        uint256 value
    ) external;
}
