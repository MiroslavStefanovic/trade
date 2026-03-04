// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ICeftaAgreement } from "./interfaces/ICeftaAgreement.sol";
import { ITradeDefinitions } from "./interfaces/ITradeDefinitions.sol";

/// @title CeftaTradeContract
/// @notice Represents a real-world trade contract and applies CEFTA quotas.
/// @dev Trade becomes active after importer signs; quotas update at activation.
contract CeftaTradeContract is ITradeDefinitions {

    address public exporterAccount;

    uint256 public quantity;

    uint256 public value;

    bool public active;

    uint16 public exporterCountry;

    uint16 public importerCountry;

    address public importerAccount;

    string public hsCode;

    ICeftaAgreement public immutable agreement;

    address private _pendingApprover;

    uint256 private _pendingQuantity;

    uint256 private _pendingValue;

    bool private _pendingActive;

    constructor(TradeDetails memory details, address agreementAddress) {
        require(agreementAddress.code.length > 0, "Invalid agreement");
        agreement = ICeftaAgreement(agreementAddress);
        hsCode = details.hsCode;
        quantity = details.quantity;
        value = details.value;
        exporterAccount = details.exporter.account;
        exporterCountry = details.exporter.country;
        importerAccount = details.importer.account;
        importerCountry = details.importer.country;
        active = true;
    }

    function approveUpdate(
        uint256 newQuantity,
        uint256 newValue,
        bool newActive
    ) external onlyParticipant {
        if (_pendingApprover == address(0)) {
            _pendingApprover = msg.sender == exporterAccount
                ? importerAccount
                : exporterAccount;
            _pendingQuantity = newQuantity;
            _pendingValue = newValue;
            _pendingActive = newActive;
            return;
        }

        require(msg.sender == _pendingApprover, "Only counterparty");
        require(_pendingQuantity == newQuantity, "Quantity mismatch");
        require(_pendingValue == newValue, "Value mismatch");
        require(_pendingActive == newActive, "Active mismatch");

        _applyUpdate(newQuantity, newValue, newActive);
    }

    function _applyUpdate(
        uint256 newQuantity,
        uint256 newValue,
        bool newActive
    ) private {
        if (newQuantity != quantity) {
            agreement.updateTradeQuantity(
                exporterCountry,
                importerCountry,
                hsCode,
                quantity,
                newQuantity
            );
            quantity = newQuantity;
        }

        value = newValue;
        active = newActive;

        _pendingApprover = address(0);
    }

    modifier onlyParticipant() {
        require(
            msg.sender == exporterAccount || msg.sender == importerAccount,
            "Only participant"
        );
        _;
    }
}
