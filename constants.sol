// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

contract Constants {
    // Program configuration seed
    string public constant PROGRAM_CONFIG_SEED = "program_config";

    // Fee recipient identifier
    string public constant FEE_RECIPIENT = "fee_recipient";

    // Quote token information seed
    string public constant QUOTE_TOKEN_INFO_SEED = "quote_token_info";

    // Fee recipient quote seed
    string public constant FEE_RECIPIENT_QUOTE_SEED = "fee_recipient_quote";

    // Bonding curve seed
    string public constant BONDING_CURVE_SEED = "bonding_curve";

    // Bonding curve quote seed
    string public constant BONDING_CURVE_QUOTE_SEED = "bonding_curve_quote";

    // Bonding curve base seed
    string public constant BONDING_CURVE_BASE_SEED = "bonding_curve_base";

    // Update configuration action types
    uint8 public constant UPDATE_CONFIG_ACTION_ADMIN = 0;
    uint8 public constant UPDATE_CONFIG_ACTION_PLATFORM = 1;
    uint8 public constant UPDATE_CONFIG_ACTION_FEE_RECIPIENT = 2;
    uint8 public constant UPDATE_CONFIG_ACTION_DEPOSIT = 3;
}
