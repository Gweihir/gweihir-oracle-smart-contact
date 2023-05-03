// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract GeneralConsumer is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;


    // Chainlink payment info
    uint256 private constant ORACLE_PAYMENT = 1 * LINK_DIVISIBILITY;

    // Mapping to store the different type of requests results
    mapping(bytes32 => uint256) public uintRequestResults;     // requestID => result (uint256)
    mapping(bytes32 => string) public stringRequestResults;    // requestID => result (string)
    mapping(bytes32 => bool) public boolRequestResults;        // requestID => result (bool)

    // Values to specify the request type and the access the request result
    uint256 public constant STRING_REQUEST_TYPE = 1;
    uint256 public constant UINT_REQUEST_TYPE = 2;
    uint256 public constant BOOL_REQUEST_TYPE = 3;

    // Last requestID value
    bytes32 public lastRequestId;

    // Request events
    event RequestUintValueFulfilled(bytes32 indexed _requestId, uint256 indexed _requestResult);
    event RequestStringValueFulfilled(bytes32 indexed _requestId, string indexed _requestResult);
    event RequestBoolValueFulfilled(bytes32 indexed _requestId, bool indexed _requestResult);

    event RequestKusamaAccountBalanceFulfilled(bytes32 indexed requestId, uint256 indexed freePlank);

    uint256 public currentAccountBalance;

    constructor(address _link) ConfirmedOwner(msg.sender) {
        if (_link == address(0)) {
            setPublicChainlinkToken();
        } else {
            setChainlinkToken(_link);
        }
    }

    function requestValue(address _oracle, string memory _jobId, uint256 resultType, string[] memory requestParamNames, string[] memory requestParamValues) public {

        require(requestParamNames.length == requestParamValues.length, "Parameters and values amounts don't match");

        uint256 paramsLength = requestParamNames.length;

        Chainlink.Request memory req;

        if (resultType == UINT_REQUEST_TYPE) {
            req = buildChainlinkRequest(
                stringToBytes32(_jobId),            // JobID for the function on the Chainlink node operator 
                address(this),                      // Request maker
                this.fullfillUintRequest.selector   // Function that is entitled to store the request result
            );
        } else if (resultType == STRING_REQUEST_TYPE) {
            req = buildChainlinkRequest(
                stringToBytes32(_jobId),            // JobID for the function on the Chainlink node operator 
                address(this),                      // Request maker
                this.fullfillStringRequest.selector // Function that is entitled to store the request result
            );
        } else if (resultType == BOOL_REQUEST_TYPE) {
            req = buildChainlinkRequest(
                stringToBytes32(_jobId),            // JobID for the function on the Chainlink node operator 
                address(this),                      // Request maker
                this.fullfillBoolRequest.selector   // Function that is entitled to store the request result
            );
        }

        // Add all the couples (param,value) to the request
        for (uint256 i = 0; i < paramsLength; i++ ) {
            req.add(requestParamNames[i], requestParamValues[i]);
        }

        sendChainlinkRequestTo(_oracle, req, ORACLE_PAYMENT);
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

    function requestKusamaAccountBalance(address _oracle, string memory _jobId, string memory kusamaAddress, string memory kusamaBlockHash) public onlyOwner {
        Chainlink.Request memory req = buildChainlinkRequest(
            stringToBytes32(_jobId),
            address(this),
            this.fulfillKusamaAccountBalance.selector
        );
        req.add("address", kusamaAddress);
        req.add("blockHash", kusamaBlockHash);
        req.add("path", "data,free");
        sendChainlinkRequestTo(_oracle, req, ORACLE_PAYMENT);
    }

    function fulfillKusamaAccountBalance(bytes32 requestId, uint256 freePlank ) public recordChainlinkFulfillment(requestId) {
        emit RequestKusamaAccountBalanceFulfilled(requestId, freePlank);
        currentAccountBalance = freePlank;
    }

    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }

    function cancelRequest(bytes32 _requestId, uint256 _payment, bytes4 _callbackFunctionId, uint256 _expiration) public onlyOwner {
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

    // Retrieve result functions
    function getUintRequestResult(bytes32 requestId) external view returns(uint256) {
        return uintRequestResults[requestId];
    }

    function getStringRequestResult(bytes32 requestId) external view returns(string memory) {
        return stringRequestResults[requestId];
    }

    function getBoolRequestResult(bytes32 requestId) external view returns(bool) {
        return boolRequestResults[requestId];
    }
}
