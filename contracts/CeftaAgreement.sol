// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CeftaGovernance } from "./CeftaGovernance.sol";
import { ITradeDefinitions } from "./interfaces/ITradeDefinitions.sol";

/// @title CeftaAgreement
/// @notice Agreement registry with unanimous member governance and annex data.
/// @dev
/// Business flow:
/// - Members propose actions encoded as (ActionType, params) and approve them.
/// - Once every current member has approved, the action can be executed.
/// - Annex data (HS codes, quotas) is only mutated via governance.
/// - Trade contract is explicitly authorized to record trades.
contract CeftaAgreement is ITradeDefinitions {
    address public ceftaTrade;

    address public admin;

    address public governance;

    uint256 public memberCount;

    bool public agreementActive;

    /// @notice Current member list.
    Party[] private _members;

    /// @notice Membership lookup.
    mapping(address => bool) public isMember;

    mapping(string => bool) public allowedHS;

    mapping(uint16 => mapping(uint16 => mapping(string => Quota)))
        public countryQuotas;

    /// @notice Country code membership lookup.
    mapping(uint16 => bool) private _isMemberCountry;

    mapping(address => bool) public signedContracts;

    struct Quota {
        uint256 max;
        uint256 used;
    }

    /// @param initialMembers Initial CEFTA member addresses.
    constructor(address[] memory initialMembers) {
        admin = msg.sender;
        _initMembers(initialMembers);
    }

    /// @notice Returns the active member list.
    /// @dev The list is not ordered and may change as members are added/removed.
    function getMembers() external view returns (Party[] memory) {
        return _members;
    }

    function quotaAvailable(
        uint16 exporterCountry,
        uint16 importerCountry,
        string memory hsCode
    ) external view returns (uint256) {
        require(exporterCountry != 0, "Invalid exporter");
        require(importerCountry != 0, "Invalid importer");
        require(allowedHS[hsCode], "HS not allowed");
        Quota memory quota = countryQuotas[exporterCountry][importerCountry][
            hsCode
        ];
        return quota.max - quota.used;
    }

    function recordTrade(
        Party memory exporter,
        Party memory importer,
        string memory hsCode,
        uint256 quantity,
        uint256
    ) external onlyCeftaTrade {
        Quota storage quota = countryQuotas[exporter.country][importer.country][
            hsCode
        ];
        require(quota.used + quantity <= quota.max, "Quota exceeded");
        quota.used += quantity;
    }

    function updateTradeQuantity(
        uint16 exporterCountry,
        uint16 importerCountry,
        string memory hsCode,
        uint256 oldQuantity,
        uint256 newQuantity
    ) external onlyTradeUpdater {
        Quota storage quota = countryQuotas[exporterCountry][importerCountry][
            hsCode
        ];
        if (newQuantity > oldQuantity) {
            uint256 delta = newQuantity - oldQuantity;
            require(quota.used + delta <= quota.max, "Quota exceeded");
            quota.used += delta;
        } else if (oldQuantity > newQuantity) {
            uint256 delta = oldQuantity - newQuantity;
            quota.used -= delta;
        }
    }

    function registerTradeContract(address tradeContract) external onlyCeftaTrade {
        require(tradeContract != address(0), "Invalid trade");
        signedContracts[tradeContract] = true;
    }

    function _initMembers(address[] memory initialMembers) internal {
        require(initialMembers.length > 0, "No members");
        for (uint256 i = 0; i < initialMembers.length; i++) {
            address member = initialMembers[i];
            require(member != address(0), "Invalid member");
            require(!isMember[member], "Duplicate member");
            isMember[member] = true;
            _members.push(Party({ account: member, country: 0 }));
        }
        memberCount = initialMembers.length;
    }

    function addMember(address member, uint16 country) external onlyGovernance {
        require(member != address(0), "Invalid member");
        require(country != 0, "Invalid country");
        require(!_isMemberCountry[country], "Country exists");
        if (isMember[member]) {
            for (uint256 i = 0; i < _members.length; i++) {
                if (_members[i].account == member) {
                    require(_members[i].country == 0, "Country set");
                    _members[i].country = country;
                    _isMemberCountry[country] = true;
                    return;
                }
            }
            revert("Member not found");
        }
        isMember[member] = true;
        _members.push(Party({ account: member, country: country }));
        _isMemberCountry[country] = true;
        memberCount += 1;
    }

    function removeMember(address member) external onlyGovernance {
        require(isMember[member], "Member not found");
        require(memberCount > 1, "Cannot remove last member");

        isMember[member] = false;
        memberCount -= 1;

        for (uint256 i = 0; i < _members.length; i++) {
            if (_members[i].account == member) {
                if (_members[i].country != 0) {
                    _isMemberCountry[_members[i].country] = false;
                }
                _members[i] = _members[_members.length - 1];
                _members.pop();
                break;
            }
        }

    }

    function isMemberCountry(uint16 country) external view returns (bool) {
        return _isMemberCountry[country];
    }

    function setHSCode(string memory hsCode) external onlyGovernance {
        allowedHS[hsCode] = true;
    }

    function setQuota(
        uint16 exporterCountry,
        uint16 importerCountry,
        string memory hsCode,
        uint256 maxAmount
    ) external onlyGovernance {
        countryQuotas[exporterCountry][importerCountry][hsCode] = Quota(
            maxAmount,
            0
        );
    }

    function setAgreementActive(bool active) external onlyGovernance {
        agreementActive = active;
    }

    function setCeftaTrade(address trade) external onlyGovernance {
        require(trade != address(0), "Invalid trade");
        ceftaTrade = trade;
    }

    function setGovernance(address governanceAddress) external onlyAdmin {
        require(governance == address(0), "Governance already set");
        require(governanceAddress.code.length > 0, "Invalid governance");
        require(
            address(CeftaGovernance(governanceAddress).agreement()) ==
                address(this),
            "Governance mismatch"
        );
        governance = governanceAddress;
    }

    modifier onlyCeftaTrade() {
        require(msg.sender == ceftaTrade, "Not trade");
        _;
    }

    modifier onlyGovernance() {
        require(governance != address(0), "Governance not set");
        require(msg.sender == governance, "Not governance");
        _;
    }

    modifier onlyTradeContract() {
        require(signedContracts[msg.sender], "Not trade");
        _;
    }

    modifier onlyTradeUpdater() {
        require(
            msg.sender == ceftaTrade || signedContracts[msg.sender],
            "Not trade"
        );
        _;
    }

    modifier onlyMember() {
        require(isMember[msg.sender], "Not member");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }
}
