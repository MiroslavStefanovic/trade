// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ICeftaAgreement } from "./interfaces/ICeftaAgreement.sol";
import { ITradeDefinitions } from "./interfaces/ITradeDefinitions.sol";

/// @title CeftaGovernance
/// @notice Unanimous member governance for CEFTA agreement actions.
/// @dev Stores annex state and governance execution logic.
contract CeftaGovernance is ITradeDefinitions {

    /// @notice Supported governance action types.
    enum ActionType {
        AddMember,
        RemoveMember,
        AddHSCode,
        SetQuota,
        SetAgreementActive,
        SetCeftaTrade
    }

    /// @notice Governance action stored by its payload hash.
    /// @dev The payload is the canonical bytes representation of the action.
    struct Action {
        /// @notice ABI-encoded payload (ActionType, params).
        bytes payload;
        /// @notice Member that proposed the action.
        address proposer;
        /// @notice Number of approvals collected.
        uint256 approvals;
        /// @notice True once executed.
        bool executed;
    }

    /// @notice Actions keyed by payload hash.
    /// @dev The actionId must be keccak256(payload).
    mapping(bytes32 => Action) public actions;

    /// @notice Per-member approvals for actions.
    /// @dev Used to enforce unanimous approval.
    mapping(bytes32 => mapping(address => bool)) public actionApprovals;

    ICeftaAgreement public immutable agreement;

    constructor(address agreementAddress) {
        require(agreementAddress.code.length > 0, "Invalid agreement");
        agreement = ICeftaAgreement(agreementAddress);
    }

    /// @notice Propose a governance action.
    /// @dev The proposer is auto-approved.
    /// @param actionId Keccak256 hash of the payload.
    /// @param payload ABI-encoded (ActionType, bytes params).
    function proposeAction(bytes32 actionId, bytes calldata payload)
        external
        onlyMember
    {
        require(payload.length > 0, "Empty payload");
        require(actionId == keccak256(payload), "Action id mismatch");
        Action storage action = actions[actionId];
        require(action.payload.length == 0, "Action already exists");

        action.payload = payload;
        action.proposer = msg.sender;
        action.approvals = 1;
        action.executed = false;
        actionApprovals[actionId][msg.sender] = true;

        emit ActionProposed(actionId, msg.sender);
        emit ActionApproved(
            actionId,
            msg.sender,
            action.approvals,
            agreement.memberCount()
        );
    }

    /// @notice Approve a governance action.
    /// @dev Each member can approve only once.
    /// @param actionId Keccak256 hash of the payload.
    function approveAction(bytes32 actionId) external onlyMember {
        Action storage action = actions[actionId];
        require(action.payload.length > 0, "Action not found");
        require(!action.executed, "Action executed");
        require(!actionApprovals[actionId][msg.sender], "Already approved");

        actionApprovals[actionId][msg.sender] = true;
        action.approvals += 1;

        emit ActionApproved(
            actionId,
            msg.sender,
            action.approvals,
            agreement.memberCount()
        );
    }

    /// @notice Execute a fully approved governance action.
    /// @dev Removal requires approval by the member being removed.
    /// @param actionId Keccak256 hash of the payload.
    function executeAction(bytes32 actionId) external onlyMember {
        Action storage action = actions[actionId];
        require(action.payload.length > 0, "Action not found");
        require(!action.executed, "Action executed");
        require(
            action.approvals == agreement.memberCount(),
            "Not fully approved"
        );

        action.executed = true;

        (ActionType actionType, bytes memory params) = abi.decode(
            action.payload,
            (ActionType, bytes)
        );

        if (actionType == ActionType.RemoveMember) {
            address subjectMember = abi.decode(params, (address));
            require(
                actionApprovals[actionId][subjectMember],
                "Member approval required"
            );
        }

        _executeAction(actionType, params);
        emit ActionExecuted(actionId, actionType);
    }

    function _executeAction(ActionType actionType, bytes memory params) internal {
        if (actionType == ActionType.AddMember) {
            (address newMember, uint16 country) = abi.decode(
                params,
                (address, uint16)
            );
            agreement.addMember(newMember, country);
            emit MemberAdded(newMember);
        } else if (actionType == ActionType.RemoveMember) {
            address member = abi.decode(params, (address));
            agreement.removeMember(member);
            emit MemberRemoved(member);
        } else if (actionType == ActionType.AddHSCode) {
            string memory hsCode = abi.decode(params, (string));
            agreement.setHSCode(hsCode);
            emit HSCodeAdded(hsCode);
        } else if (actionType == ActionType.SetQuota) {
            (
                uint16 exporterCountry,
                uint16 importerCountry,
                string memory hsCode,
                uint256 maxAmount
            ) = abi.decode(params, (uint16, uint16, string, uint256));
            agreement.setQuota(
                exporterCountry,
                importerCountry,
                hsCode,
                maxAmount
            );
            emit QuotaSet(exporterCountry, importerCountry, hsCode, maxAmount);
        } else if (actionType == ActionType.SetAgreementActive) {
            bool active = abi.decode(params, (bool));
            agreement.setAgreementActive(active);
            emit AgreementActiveSet(active);
        } else if (actionType == ActionType.SetCeftaTrade) {
            address trade = abi.decode(params, (address));
            agreement.setCeftaTrade(trade);
            emit CeftaTradeSet(trade);
        } else {
            revert("Unknown action");
        }
    }

    /// @notice Emitted when a governance action is proposed.
    event ActionProposed(bytes32 indexed actionId, address indexed proposer);
    /// @notice Emitted when a member approves a governance action.
    event ActionApproved(
        bytes32 indexed actionId,
        address indexed approver,
        uint256 approvals,
        uint256 required
    );
    /// @notice Emitted when a governance action is executed.
    event ActionExecuted(bytes32 indexed actionId, ActionType actionType);
    /// @notice Emitted when a member is added.
    event MemberAdded(address indexed member);
    /// @notice Emitted when a member is removed.
    event MemberRemoved(address indexed member);
    /// @notice Emitted when an HS code is added.
    event HSCodeAdded(string hsCode);
    /// @notice Emitted when a quota is set.
    event QuotaSet(
        uint16 exporterCountry,
        uint16 importerCountry,
        string hsCode,
        uint256 maxAmount
    );
    /// @notice Emitted when the agreement active flag changes.
    event AgreementActiveSet(bool active);
    /// @notice Emitted when the CEFTA trade address is set.
    event CeftaTradeSet(address indexed ceftaTrade);
    modifier onlyMember() {
        require(agreement.isMember(msg.sender), "Not a member");
        _;
    }
}
