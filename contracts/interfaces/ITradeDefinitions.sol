// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Shared trade data and events.
interface ITradeDefinitions {

    struct Party {
        address account;
        /// @notice ISO 3166 numeric country code.
        uint16 country;
    }

    struct TradeDetails {
        string hsCode;
        uint256 quantity;
        uint256 value;
        Party exporter;
        Party importer;
    }

    event TradeActivated(address indexed exporter, address indexed importer);
    event TradeCreated(
        address indexed tradeContract,
        address indexed exporterAccount,
        address indexed importerAccount,
        string hsCode,
        uint256 quantity,
        uint256 value
    );
    event TradeSubmitted(
        uint256 indexed tradeId,
        Party exporter,
        Party importer,
        string hsCode,
        uint256 quantity,
        uint256 value
    );
}
