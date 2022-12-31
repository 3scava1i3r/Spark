// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {IInstantDistributionAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";


abstract contract SuperPool is Ownable, SuperAppBase, Initializable {


    struct ShareholderUpdate {
      address shareholder;
      int96 previousFlowRate;
      int96 currentFlowRate;
      ISuperToken token;
    }

    struct Market {
        ISuperToken inputToken;
        uint256 lastDistributionAt; // The last time a distribution was made
        //uint256 rateTolerance; // The percentage to deviate from the oracle scaled to 1e6
        uint128 feeRate;
        //uint128 affiliateFee;
        address owner; // The owner of the market (reciever of fees)
        ISuperToken outputToken; // output supertoken PToken
        //mapping(ISuperToken => OracleInfo) oracles; // Maps tokens to their oracle info
        //mapping(uint32 => OutputPool) outputPools; // Maps IDA indexes to their distributed Supertokens
        //mapping(ISuperToken => uint32) outputPoolIndicies; // Maps tokens to their IDA indexes in OutputPools
        //uint8 numOutputPools; // Indexes outputPools and outputPoolFees
        
    }


    ISuperfluid internal host; // Superfluid host contract
    IConstantFlowAgreementV1 internal cfa; // The stored constant flow agreement class address
    IInstantDistributionAgreementV1 internal ida; // The stored instant dist. agreement class address
    //ITellor public oracle; // Address of deployed simple oracle for input//output token
    Market internal market;
    // uint32 internal constant PRIMARY_OUTPUT_INDEX = 0;
    // uint8 internal constant MAX_OUTPUT_POOLS = 5;



    // TODO: Emit these events where appropriate
    /// @dev Distribution event. Emitted on each token distribution operation.
    /// @param totalAmount is total distributed amount
    /// @param feeCollected is fee amount collected during distribution
    /// @param token is distributed token address

    event Distribution(
        uint256 totalAmount,
        uint256 feeCollected,
        address token
    );


    constructor(
        address _owner,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        IInstantDistributionAgreementV1 _ida,
        string memory _registrationKey
    ) {
        host = _host;
        cfa = _cfa;
        ida = _ida;

        transferOwnership(_owner);

        uint256 _configWord = SuperAppDefinitions.APP_LEVEL_FINAL;

        if (bytes(_registrationKey).length > 0) {
            host.registerAppWithKey(_configWord, _registrationKey);
        } else {
            host.registerApp(_configWord);
        }
    }

        /// @dev Allows anyone to close any stream if the app is jailed.
    /// @param streamer is stream source (streamer) address
    function emergencyCloseStream(address streamer, ISuperToken token) external virtual {
        // Allows anyone to close any stream if the app is jailed
        require(host.isAppJailed(ISuperApp(address(this))), "!jailed");

        host.callAgreement(
            cfa,
            abi.encodeWithSelector(
                cfa.deleteFlow.selector,
                token,
                streamer,
                address(this),
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }


    /// @dev Close stream from `streamer` address if balance is less than 8 hours of streaming
    /// @param streamer is stream source (streamer) address
    function closeStream(address streamer, ISuperToken token) public {
      // Only closable iff their balance is less than 8 hours of streaming
      (,int96 streamerFlowRate,,) = cfa.getFlow(token, streamer, address(this));
      // int96 streamerFlowRate = getStreamRate(token, streamer);
      require(int(token.balanceOf(streamer)) <= streamerFlowRate * 8 hours,
                "!closable");

      // Close the streamers stream
      // Does this trigger before/afterAgreementTerminated
      host.callAgreement(
          cfa,
          abi.encodeWithSelector(
              cfa.deleteFlow.selector,
              token,
              streamer,
              address(this),
              new bytes(0) // placeholder
          ),
          "0x"
      );
    }

    /// @dev Drain contract's input and output tokens balance to owner if SuperApp dont have any input streams.
    function emergencyDrain(ISuperToken token) external virtual onlyOwner {
        require(host.isAppJailed(ISuperApp(address(this))), "!jailed");

        token.transfer(
            owner(),
            token.balanceOf(address(this))
        );
    }

    // Setters

    // /// @dev Set rate tolerance
    // /// @param _rate This is the new rate we need to set to
    // function setRateTolerance(uint256 _rate) external onlyOwner {
    //     market.rateTolerance = _rate;
    // }

    /// @dev Sets fee rate for a output pool/token
    // /// @param _index IDA index for the output pool/token
    /// @param _feeRate Fee rate for the output pool/token
    function setFeeRate(uint128 _feeRate) external onlyOwner {
        //market.outputPools[_index].feeRate = _feeRate;
        market.feeRate = _feeRate;
    }

    // /// @dev Sets emission rate for a output pool/token
    // /// @param _index IDA index for the output pool/token
    // /// @param _emissionRate Emission rate for the output pool/token
    // function setEmissionRate(uint32 _index, uint128 _emissionRate)
    //     external
    //     onlyOwner
    // {
    //     market.outputPools[_index].emissionRate = _emissionRate;
    // }

    // Getters

    /// @dev Get input token address
    /// @return input token address
    function getInputToken() external view returns (ISuperToken) {
        return market.inputToken;
    }

    /// @dev Get output token address
    /// @return output token address
    function getOutputPool()
        external
        view
        returns (ISuperToken)
    {
        return market.outputToken;
    }

    /// @dev Get last distribution timestamp
    /// @return last distribution timestamp
    function getLastDistributionAt() external view returns (uint256) {
        return market.lastDistributionAt;
    }

    /// @dev Is app jailed in SuperFluid protocol
    /// @return is app jailed in SuperFluid protocol
    function isAppJailed() external view returns (bool) {
        return host.isAppJailed(this);
    }

    // /// @dev Get rate tolerance
    // /// @return Rate tolerance scaled to 1e6
    // function getRateTolerance() external view returns (uint256) {
    //     return market.rateTolerance;
    // }

    /// @dev Get fee rate for a given output pool/token
    /// @return Fee rate for the output pool
    function getFeeRate() external view returns (uint128) {
        return market.feeRate;
    }

    // /// @dev Get emission rate for a given output pool/token
    // /// @param _index IDA index for the output pool/token
    // /// @return Emission rate for the output pool
    // function getEmissionRate(uint32 _index) external view returns (uint256) {
    //     return market.outputPools[_index].emissionRate;
    // }

    // Custom functionality that needs to be overrided by contract extending the base

    // Lending main functions
    function distribute(bytes memory _ctx)
        public
        virtual
        returns (bytes memory _newCtx);

    // Market initialization methods

    function initializeMarket(
        ISuperToken _inputToken,
        //uint256 _rateTolerance,
        uint128 _feeRate
        // outputToken
    ) public virtual onlyOwner {
        require(
            address(market.inputToken) == address(0),
            "Already initialized"
        );
        market.inputToken = _inputToken;
        //market.rateTolerance = _rateTolerance;
        market.feeRate = _feeRate;
        //market.outputToken = _outputToken;
    }


    // Standardized functionality for all SuperPool Markets


    /// @dev Get flow rate for `_streamer`
    /// @param _streamer is streamer address
    /// @return _requesterFlowRate `_streamer` flow rate
    function getStreamRate(address _streamer, ISuperToken _token)
        external
        view
        returns (int96 _requesterFlowRate)
    {
        (, _requesterFlowRate, , ) = cfa.getFlow(
            _token,
            _streamer,
            address(this)
        );
    }


    // MAYBE===============================>
    /// @dev Get `_streamer` IDA subscription info for token with index `_index`
    /// @param _index is token index in IDA
    /// @param _streamer is streamer address
    /// @return _exist Does the subscription exist?
    /// @return _approved Is the subscription approved?
    /// @return _units Units of the suscription.
    /// @return _pendingDistribution Pending amount of tokens to be distributed for unapproved subscription.
    function getIDAShares(uint32 _index, address _streamer)
        public
        view
        returns (
            bool _exist,
            bool _approved,
            uint128 _units,
            uint256 _pendingDistribution
        )
    {
        (_exist, _approved, _units, _pendingDistribution) = ida.getSubscription(
            market.outputPools[_index].token,
            address(this),
            _index,
            _streamer
        );
    }

    function _updateShareholder(
        bytes memory _ctx,
        ShareholderUpdate memory _shareholderUpdate
    ) internal virtual returns (bytes memory _newCtx) {
        // We need to go through all the output tokens and update their IDA shares
        _newCtx = _ctx;
        (uint128 userShares, uint128 daoShares) = _getShareAllocations(_shareholderUpdate);
        // updateOutputPool

            _newCtx = _updateSubscriptionWithContext(
                _newCtx,
                _index,
                _shareholderUpdate.shareholder,
                // shareholder gets 99.7% of the units, DAO takes .3%
                userShares,
                market.outputToken
            );
            _newCtx = _updateSubscriptionWithContext(
                _newCtx,
                _index,
                owner(),
                // shareholder gets 99.7% of the units, DAO takes .3%
                daoShares,
                market.outputToken
            );
            
            // TODO: Update the fee taken by the DAO
        

    }



    function _getShareAllocations(ShareholderUpdate memory _shareholderUpdate)
     internal returns (uint128 userShares, uint128 daoShares)
    {
      (,,daoShares,) = getIDAShares(market.outputPoolIndicies[_shareholderUpdate.token], owner());
      daoShares *= market.outputPools[market.outputPoolIndicies[_shareholderUpdate.token]].shareScaler;

    //   if (address(0) != _shareholderUpdate.affiliate) {
    //     (,,affiliateShares,) = getIDAShares(market.outputPoolIndicies[_shareholderUpdate.token], _shareholderUpdate.affiliate);
    //     affiliateShares *= market.outputPools[market.outputPoolIndicies[_shareholderUpdate.token]].shareScaler;
    //   }

      // Compute the change in flow rate, will be negative is slowing the flow rate
      int96 changeInFlowRate = _shareholderUpdate.currentFlowRate - _shareholderUpdate.previousFlowRate;
      uint128 feeShares;
      // if the change is positive value then DAO has some new shares,
      // which would be 2% of the increase in shares
      if(changeInFlowRate > 0) {
        // Add new shares to the DAO
        feeShares = uint128(uint256(int256(changeInFlowRate)) * market.feeRate / 1e6);
        // if (address(0) != _shareholderUpdate.affiliate) {
        //   affiliateShares += feeShares * market.affiliateFee / 1e6;
        //   feeShares -= feeShares * market.affiliateFee / 1e6;
        // }
        daoShares += feeShares;
      } else {
        // Make the rate positive
        changeInFlowRate = -1 * changeInFlowRate;
        feeShares = uint128(uint256(int256(changeInFlowRate)) * market.feeRate / 1e6);
        // if (address(0) != _shareholderUpdate.affiliate) {
        //   affiliateShares -= (feeShares * market.affiliateFee / 1e6 > affiliateShares) ? affiliateShares : feeShares * market.affiliateFee / 1e6;
        //   feeShares -= feeShares * market.affiliateFee / 1e6;
        // }
        daoShares -= (feeShares > daoShares) ? daoShares : feeShares;
      }
      userShares = uint128(uint256(int256(_shareholderUpdate.currentFlowRate))) * (1e6 - market.feeRate) / 1e6;

      // Scale back shares
      daoShares /= market.outputPools[market.outputPoolIndicies[_shareholderUpdate.token]].shareScaler;
      userShares /= market.outputPools[market.outputPoolIndicies[_shareholderUpdate.token]].shareScaler;

    }

    function _getShareholderInfo(bytes calldata _agreementData, ISuperToken _superToken)
        internal
        view
        returns (address _shareholder, int96 _flowRate, uint256 _timestamp)
    {
        (_shareholder, ) = abi.decode(_agreementData, (address, address));
        (_timestamp, _flowRate, , ) = cfa.getFlow(
            _superToken,
            _shareholder,
            address(this)
        );
    }









        // Superfluid Agreement Management Methods

    function _createIndex(uint256 index, ISuperToken distToken) internal {
        host.callAgreement(
            ida,
            abi.encodeWithSelector(
                ida.createIndex.selector,
                distToken,
                index,
                new bytes(0) // placeholder ctx
            ),
            new bytes(0) // user data
        );
    }

    /// @dev Set new `shares` share for `subscriber` address in IDA with `index` index
    /// @param index IDA index ID
    /// @param subscriber is subscriber address
    /// @param shares is distribution shares count
    /// @param distToken is distribution token address
    function _updateSubscription(
        uint256 index,
        address subscriber,
        uint128 shares,
        ISuperToken distToken
    ) internal {
        host.callAgreement(
            ida,
            abi.encodeWithSelector(
                ida.updateSubscription.selector,
                distToken,
                index,
                subscriber,
                shares,
                new bytes(0) // placeholder ctx
            ),
            new bytes(0) // user data
        );
    }

        /// @dev Same as _updateSubscription but uses provided SuperFluid context data
    /// @param ctx SuperFluid context data
    /// @param index IDA index ID
    /// @param subscriber is subscriber address
    /// @param shares is distribution shares count
    /// @param distToken is distribution token address
    /// @return newCtx updated SuperFluid context data
    function _updateSubscriptionWithContext(
        bytes memory ctx,
        uint256 index,
        address subscriber,
        uint128 shares,
        ISuperToken distToken
    ) internal returns (bytes memory newCtx) {
        newCtx = ctx;
        (newCtx, ) = host.callAgreementWithContext(
            ida,
            abi.encodeWithSelector(
                ida.updateSubscription.selector,
                distToken,
                index,
                subscriber,
                shares,
                new bytes(0)
            ),
            new bytes(0), // user data
            newCtx
        );
    }



}