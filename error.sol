// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

library ErrorCode {
    string public constant InvalidAdmin = "Invalid admin.";
    string public constant InvalidParameters = "Invalid parameters.";
    string public constant InvalidInputUpdateParam = "Invalid input update param.";
    string public constant QuoteTokenDeleted = "Quote token is deleted.";
    string public constant InvalidInputSupply = "Invalid input supply.";
    string public constant OnPancake = "This token is on Pancake, please swap on Pancake.";
    string public constant ExceededSlippage = "Exceeds desired slippage limit.";
    string public constant NotEnoughTokens = "Not enough tokens to sell.";
    string public constant InvalidCreator = "Invalid creator.";
    string public constant InvalidPlatform = "Invalid platform.";
    string public constant OnBondingCurve = "This token is on the bonding curve.";
    string public constant InvalidFeeBps = "Invalid fee bps.";
    string public constant AlreadyInitialized = "Already initialized.";
    string public constant Unauthorized = "Unauthorized for Collection.";
    string public constant NotInitialized = "Not initialized.";
}
