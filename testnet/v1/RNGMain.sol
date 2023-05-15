// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev Apeiron
/// @title RandomNumberGenerationMain
contract RandomNumberGenerationMain {
    uint256 private constant PERCENT_DIVIDER = 1e3;
    uint256 private nonce;

    constructor() {}
    /// @notice Returns true or false, depending on whether the upgrade worked or is burned (upgrade failed).
    /// @dev Pseudo-random number generation is satisfyingly random, as it uses non-deterministic variables.
    /// @dev Success probability depends on the given rarity of the weapon, with difficulty increasing exponentially.
    /// @dev Weapon upgrade probability to fail is (1 / exp(n + 1)) * 100.
    /// @param rarity Weapon ID to compute the reward from.
    /// @return True or false: upgrade succeeds or fails.
    function weaponUpgradeAllowedOrFail(uint128 rarity) internal returns (bool) {
        uint256 probability = weaponUpgradeProbability(rarity);
        uint256 random_number = generateNumber();

        return random_number <= probability;
    }

    /// @notice Description for the end user.
    /// @dev Description for a developer or auditor.
    /// @param rarity Description of the parameter.
    /// @return What this function returns.
    function weaponUpgradeProbability(uint128 rarity) internal pure returns (uint256) {
        uint256 formula = 60 - ((rarity - 1) * 4);

        return formula * PERCENT_DIVIDER;
    }

    /// @notice Description for the end user.
    /// @dev Description for a developer or auditor.
    /// @param rarity Description of the parameter.
    /// @return What this function returns.
    function weaponMintProbability(
        uint128 rarity
    ) internal pure returns (uint256) {
        if (rarity >= 1 && rarity <= 6) return (60 - 7 * rarity) * PERCENT_DIVIDER;
        else if (rarity == 7) return 5 * PERCENT_DIVIDER;
        else if (rarity == 8) return (6 * PERCENT_DIVIDER) / 5;
        else if (rarity == 9) return PERCENT_DIVIDER / 5;
        else return 0;
    }

    /// @notice Gets a randomly generated number and returns a rarity.
    /// @dev If generated number is smaller than probability then we have a match.
    /// @return Weapon rarity, from 1 to 9.
    function weaponMintRarity() internal returns (uint128) {
        for (uint128 i = 1; i <= 9; i++) {
            uint256 random_number = generateNumber();
            uint256 probability = weaponMintProbability(i);

            if (random_number <= probability) return i;
        }

        return 1;
    }

    /// @notice Gets a randomly generated number and returns a weapon variation.
    /// @dev Picks one weapon variation randomly.
    /// @return A weapon variation, from 0 to variation_max.
    function weaponMintVariation() internal returns (uint256) {
        uint256 variation_max = 4;

        return (generateNumber() % variation_max) + 1;
    }

    /// @notice Returns a random number from 0 to 100.
    /// @dev Pseudo-random number generation is satisfyingly random, as it uses non-deterministic variables.
    /// @dev Minimum starts at min * percent_divider, to max * percent_divider.
    /// @return ether.
    function generateNumber() internal returns (uint256) {
        uint256 max = 100 * PERCENT_DIVIDER;
        uint256 random_number = uint256(keccak256(abi.encodePacked(block.prevrandao, block.difficulty, block.timestamp, block.coinbase, msg.sender, ++nonce)));

        return random_number % max;
    }

    /// @notice Returns a random number from 0 to max.
    /// @dev Pseudo-random number generation is satisfyingly random, as it uses non-deterministic variables.
    /// @param _max Maximum number of the random number generation.
    /// @return ether.
    function generateNumberWithMax(uint256 _max) internal returns (uint256) {
        uint256 max = _max;
        uint256 random_number = uint256(keccak256(abi.encodePacked(block.prevrandao, block.difficulty, block.timestamp, block.coinbase, msg.sender, ++nonce)));

        return random_number % max;
    }
}