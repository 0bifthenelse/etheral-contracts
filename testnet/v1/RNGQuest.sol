// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev Apeiron
/// @title RandomNumberGenerationQuest
contract RandomNumberGenerationQuest {
    uint256 private constant PERCENT_DIVIDER = 1e3;
    uint256 private nonce;

    constructor() {}

    /// @notice Returns the result status of a quest, that is success or failure.
    /// @param index Quest index, which is also its difficulty.
    /// @param rarity Weapon rarity to consider in the formula.
    /// @return (status as hash, result as bool).
    function questResultStatus(uint256 index, uint128 rarity) internal returns (bytes32, bool) {
        uint256 probability_failure = questSuccessProbability(index, rarity) * PERCENT_DIVIDER;
        uint256 random_number = generateNumber();
        bool result = random_number <= probability_failure;
        bytes32 status = result ? keccak256("SUCCESS") : keccak256("FAILURE");

        require(rarity < 10, "Q: invalid weapon rarity.");

        return (status, result);
    }

    /// @notice Returns the result status of a quest, that is success or failure.
    /// @dev Adding a % success bonus is as easy as adding a number on top of this function.
    /// @param index Quest index, which is also its overall difficulty.
    /// @param rarity Weapon rarity to increase the probability of success.
    /// @return (status as hash, result as bool).
    function questSuccessProbability(uint256 index, uint128 rarity) internal pure returns (uint256) {
        uint256 size = 8;
        uint256[] memory probability_success = new uint256[](size); 
        uint256 bonus_for_rarity = rarity * 5; // up to 45% bonus

        probability_success[0] = 50; // 50% chance of success
        probability_success[1] = 40; // 40% chance of success
        probability_success[2] = 35; // 35% chance of success
        probability_success[3] = 50; // 50% chance of success
        probability_success[4] = 30; // 30% chance of success
        probability_success[5] = 40; // 40% chance of success
        probability_success[6] = 10; // 10% chance of success
        probability_success[7] = 30; // 30% chance of success

        require(index < size, "Q: Out of bound.");

        return probability_success[index] + bonus_for_rarity;
    }

    /// @notice Returns the result reward type, which is either ether or chests.
    /// @dev Pseudo-random number generation is satisfyingly random, as it uses non-deterministic variables.
    /// @dev 50% chance of returning true or false.
    /// @return Chests (true) or ether (false);
    function questResultRewardType() internal returns (bool) {
        uint256 probability = 50 * PERCENT_DIVIDER;
        uint256 random_number = generateNumber();

        return random_number <= probability;
    }

    /// @notice Returns a random number from 0 to 100.
    /// @dev Pseudo-random number generation is satisfyingly random, as it uses non-deterministic variables.
    /// @dev Minimum starts at min * percent_divider, to max * percent_divider.
    /// @return ether.
    function generateNumber() internal returns (uint256) {
        uint256 max = 100 * PERCENT_DIVIDER;
        uint256 random_number = uint256(keccak256(abi.encodePacked(block.prevrandao, block.difficulty, block.timestamp, block.coinbase, msg.sender, nonce++)));

        return random_number % max;
    }

    /// @notice Returns a random number from 0 to max.
    /// @dev Pseudo-random number generation is satisfyingly random, as it uses non-deterministic variables.
    /// @param _max Maximum number of the random number generation.
    /// @return ether.
    function generateNumberWithMax(uint256 _max) internal returns (uint256) {
        uint256 max = _max; // percent divider must be computed before function execution unlike generateNumber
        uint256 random_number = uint256(keccak256(abi.encodePacked(block.prevrandao, block.difficulty, block.timestamp, block.coinbase, msg.sender, nonce++)));

        return random_number % max;
    }
}