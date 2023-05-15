// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

struct Weapon {
  uint256 id;
  uint128 rarity;
  uint256 variation;
  bool destroyed;
}

struct Player {
  uint256 id;
  uint256 chests;
  uint256 weapon_equipped;
  uint256 quest_end;
}

interface IMain is IERC721Upgradeable {
  function getPlayer(address player) external view returns (Player memory);
  function getWeapon(uint256 id) external view returns (Weapon memory);
  function getWeaponOwner(uint256 id) external view returns (address);
  function getWeaponRarity(uint256 id) external view returns (uint128);
  function getWeaponEquipped(address player) external view returns (Weapon memory);
  function getWeaponsOwned(uint256 id) external view returns (Weapon[] memory weapons_owned);
  function getWeaponExistence(uint256 id) external view returns (bool);
  function getShareholders() external pure returns (address[] memory shareholders, uint256[] memory percents);
  function getShare(uint256 shareholder, uint256 amount) external pure returns (uint256);

  function startQuest(address _player, uint256 end) external;
  function completeQuest(address _player) external;
  function rewardChests(address _player, uint256 rewarded_chests) external;

  function safeTransferFrom(address from, address to, uint256 tokenId) external;
  function approve(address _to, uint256 _tokenId) external;
}
