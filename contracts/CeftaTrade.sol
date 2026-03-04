// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CeftaTradeContract } from "./CeftaTradeContract.sol";
import { ICeftaAgreement } from "./interfaces/ICeftaAgreement.sol";
import { ITradeDefinitions } from "./interfaces/ITradeDefinitions.sol";

/// @title CeftaTrade
/// @notice Deploys trade contracts for real-world CEFTA transactions.
/// @dev The importer calls createTrade to finalize the trade.
contract CeftaTrade is ITradeDefinitions {

    struct PendingTrade {
        TradeDetails details;
        bool exists;
        bool signed;
    }

    uint256 public nextTradeId;

    ICeftaAgreement public immutable agreement;

    mapping(uint256 => PendingTrade) public pendingTrades;

    constructor(address agreementAddress) {
        require(agreementAddress.code.length > 0, "Invalid agreement");
        agreement = ICeftaAgreement(agreementAddress);
    }

    function submitTrade(TradeDetails calldata details)
        external
        returns (uint256)
    {
        require(details.exporter.account != address(0), "Invalid exporter");
        require(details.importer.account != address(0), "Invalid importer");
        require(msg.sender == details.exporter.account, "Only exporter");
        require(details.quantity > 0, "Zero quantity");
        require(details.value > 0, "Zero value");
        require(
            agreement.isMemberCountry(details.exporter.country),
            "Exporter not member"
        );
        require(
            agreement.isMemberCountry(details.importer.country),
            "Importer not member"
        );
        require(agreement.allowedHS(details.hsCode), "HS not allowed");

        uint256 tradeId = nextTradeId;
        nextTradeId += 1;

        pendingTrades[tradeId] = PendingTrade(details, true, false);

        emit TradeSubmitted(
            tradeId,
            details.exporter,
            details.importer,
            details.hsCode,
            details.quantity,
            details.value
        );

        return tradeId;
    }

    function signTrade(uint256 tradeId) external returns (address) {
        PendingTrade storage pending = pendingTrades[tradeId];
        require(pending.exists, "Trade not found");
        require(!pending.signed, "Trade signed");
        require(
            msg.sender == pending.details.importer.account,
            "Only importer"
        );

        pending.signed = true;

        agreement.recordTrade(
            pending.details.exporter,
            pending.details.importer,
            pending.details.hsCode,
            pending.details.quantity,
            pending.details.value
        );

        CeftaTradeContract trade = new CeftaTradeContract(
            pending.details,
            address(agreement)
        );

        agreement.registerTradeContract(address(trade));

        emit TradeCreated(
            address(trade),
            pending.details.exporter.account,
            pending.details.importer.account,
            pending.details.hsCode,
            pending.details.quantity,
            pending.details.value
        );

        return address(trade);
    }

}
