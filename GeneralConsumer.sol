// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GeneralConsumer is ChainlinkClient, ConfirmedOwner, AccessControl {
    using Chainlink for Chainlink.Request;

    // Chainlink payment info
    uint256 public oraclePayment = 1 * 10**16;  // Equal to 0.01 LINK

    // Mapping to store the different type of requests results
    mapping(bytes32 => uint256) public uintRequestResults; // requestID => result (uint256)
    mapping(bytes32 => string) public stringRequestResults; // requestID => result (string)
    mapping(bytes32 => bool) public boolRequestResults; // requestID => result (bool)

    // Values to specify the request type and the access the request result
    uint256 public constant STRING_REQUEST_TYPE = 1;
    uint256 public constant UINT_REQUEST_TYPE = 2;
    uint256 public constant BOOL_REQUEST_TYPE = 3;

    // Last requestID value
    bytes32 public lastRequestId;
    mapping(address => bytes32[]) public requestsTracking;
    mapping(bytes32 => string[]) private requestParamentersNames;
    mapping(bytes32 => string[]) private requestParametersValues;

    // Link contract instance
    ERC20 private linkContractInstance;

    // Access control
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // Request events
    event RequestUintValueFulfilled(bytes32 indexed _requestId, uint256 indexed _requestResult);
    event RequestStringValueFulfilled(bytes32 indexed _requestId, string indexed _requestResult);
    event RequestBoolValueFulfilled(bytes32 indexed _requestId, bool indexed _requestResult);

    constructor(address _link) ConfirmedOwner(msg.sender) {
        if (_link == address(0)) {
            revert("You need to set a valid LINK token address");
        } else {
            setChainlinkToken(_link);
            linkContractInstance = ERC20(_link);
        }
        // Access control management
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    function payServiceFee() private {
        require(linkContractInstance.allowance(msg.sender, address(this)) >= oraclePayment, "You need to allow the contract to spent LINK tokens");
        linkContractInstance.transferFrom(msg.sender, address(this), oraclePayment);
    }

    function requestValue(
        address _oracle,
        string memory _jobId,
        uint256 resultType,
        string[] memory requestParamNames,
        string[] memory requestParamValues
    ) public returns(bytes32) {
        require(requestParamNames.length == requestParamValues.length, "Parameters and values amounts don't match");

        uint256 paramsLength = requestParamNames.length;

        // Pay service fee to the smart contract
        payServiceFee();

        // Create request for the oracle
        Chainlink.Request memory req;

        // Switch between the request types and send the request
        if (resultType == UINT_REQUEST_TYPE) {
            req = buildChainlinkRequest(
                stringToBytes32(_jobId), // JobID for the function on the Chainlink node operator
                address(this), // Request maker
                this.fullfillUintRequest.selector // Function that is entitled to store the request result
            );
        } else if (resultType == STRING_REQUEST_TYPE) {
            req = buildChainlinkRequest(
                stringToBytes32(_jobId), // JobID for the function on the Chainlink node operator
                address(this), // Request maker
                this.fullfillStringRequest.selector // Function that is entitled to store the request result
            );
        } else if (resultType == BOOL_REQUEST_TYPE) {
            req = buildChainlinkRequest(
                stringToBytes32(_jobId), // JobID for the function on the Chainlink node operator
                address(this), // Request maker
                this.fullfillBoolRequest.selector // Function that is entitled to store the request result
            );
        }

        // Add all the couples (param,value) to the request
        for (uint256 i = 0; i < paramsLength; i++) {
            req.add(requestParamNames[i], requestParamValues[i]);
        }

        bytes32 requestId = sendChainlinkRequestTo(_oracle, req, oraclePayment);
        requestsTracking[msg.sender].push(requestId);  // Add requestId to the list of the past requests
        requestParamentersNames[requestId] = requestParamNames; // Add params names for UI semplification
        requestParametersValues[requestId] = requestParamValues; // Add params values for UI semplification
        return requestId;
    }

    function fullfillStringRequest(bytes32 requestId, string memory requestResult) public recordChainlinkFulfillment(requestId) {
        lastRequestId = requestId;
        stringRequestResults[requestId] = requestResult;
        emit RequestStringValueFulfilled(requestId, requestResult);
    }

    function fullfillUintRequest(bytes32 requestId, uint256 requestResult) public recordChainlinkFulfillment(requestId) {
        lastRequestId = requestId;
        uintRequestResults[requestId] = requestResult;
        emit RequestUintValueFulfilled(requestId, requestResult);
    }

    function fullfillBoolRequest(bytes32 requestId, bool requestResult) public recordChainlinkFulfillment(requestId) {
        lastRequestId = requestId;
        boolRequestResults[requestId] = requestResult;
        emit RequestBoolValueFulfilled(requestId, requestResult);
    }

    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }

    function cancelRequest(
        bytes32 _requestId,
        uint256 _payment,
        bytes4 _callbackFunctionId,
        uint256 _expiration
    ) public onlyOwner {
        cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            // solhint-disable-line no-inline-assembly
            result := mload(add(source, 32))
        }
    }

    // Retrieve result functions -->

    function getUintRequestResult(bytes32 requestId) external view returns (uint256) {
        return uintRequestResults[requestId];
    }

    function getStringRequestResult(bytes32 requestId) external view returns (string memory) {
        return stringRequestResults[requestId];
    }

    function getBoolRequestResult(bytes32 requestId) external view returns (bool) {
        return boolRequestResults[requestId];
    }

    function getRequestParametersNames(bytes32 requestId) external view returns(string[] memory) {
        return requestParamentersNames[requestId];
    }

    function getRequestParameterValues(bytes32 requestId) external view returns(string[] memory) {
        return requestParametersValues[requestId];
    }

    function getTotalRequestsAmountPerUser(address userAddress) public view returns(uint256) {

        return requestsTracking[userAddress].length;
    }

    function getUserRequestsList(address userAddress) public view returns(bytes32[] memory) {
        return requestsTracking[userAddress];
    }

    // Permission management -->

    function addContractManagerRole(address newManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MANAGER_ROLE, newManagerAddress);
    }

    function revokeContractManagerRole(address oldManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MANAGER_ROLE, oldManagerAddress);
    }

    // Funding management --> 

    function updateOraclePayment(uint256 newPricePerRequest) external onlyRole(MANAGER_ROLE) {
        oraclePayment = newPricePerRequest;
    }

    function withdrawLink() public onlyRole(MANAGER_ROLE) {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }
}